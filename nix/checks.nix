{ pkgs, src, components, uiBuild, uiBundle, uiNodeModules, }:
let
  scripts = {
    haskell-build = {
      runtimeInputs = [ components.exes.tmux-ws components.exes.agent-daemon ];
      text = ''
        test -e ${components.library}
        test -x ${components.exes.tmux-ws}/bin/tmux-ws
        tmux-ws --help >/dev/null
        test -x ${components.exes.agent-daemon}/bin/agent-daemon
        agent-daemon --help >/dev/null
      '';
    };

    haskell-tests = {
      runtimeInputs = [
        components.tests.e2e-tests
        pkgs.bashInteractive
        pkgs.coreutils
        pkgs.git
        pkgs.tmux
      ];
      text = ''
        export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=init.defaultBranch GIT_CONFIG_VALUE_0=main
        TMUX_TMPDIR="$(mktemp -d)"
        export TMUX_TMPDIR
        SHELL=${pkgs.bashInteractive}/bin/bash
        export SHELL
        trap 'rm -rf "$TMUX_TMPDIR"' EXIT
        e2e-tests
      '';
    };

    formatting = {
      runtimeInputs = [
        pkgs.diffutils
        pkgs.findutils
        pkgs.haskellPackages.cabal-fmt
        pkgs.haskellPackages.fourmolu
        pkgs.nixfmt-classic
      ];
      text = ''
        diff -u tmux-ws.cabal <(cabal-fmt tmux-ws.cabal)
        find src app -type f -name '*.hs' -exec fourmolu -m check {} +
        nixfmt --check flake.nix nix/*.nix
      '';
    };

    hlint = {
      runtimeInputs = [ pkgs.findutils pkgs.haskellPackages.hlint ];
      text = ''
        find src app -type f -name '*.hs' -exec hlint {} +
      '';
    };

    cabal-package = {
      runtimeInputs = [ pkgs.cabal-install ];
      text = "cabal check";
    };

    ui = {
      runtimeInputs = [ pkgs.nodejs_22 pkgs.purs-tidy-bin.purs-tidy-0_10_0 ]
        ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux
        [ pkgs.playwright-test ];
      text = ''
        test -d ${uiNodeModules}/node_modules
        test -e ${uiBuild} && test -s ${uiBundle}/index.html && test -s ${uiBundle}/index.js
        purs-tidy check 'ui/src/**/*.purs'
        node --test ui/test/TerminalInput.test.mjs
        if test "$(uname)" = Linux; then
          export UI_BUNDLE=${uiBundle} NODE_PATH=${pkgs.playwright-test}/lib/node_modules
          export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers} PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
          node --test ui/test/CommandDeckLayout.test.mjs
        fi
      '';
    };

    release-plan = {
      runtimeInputs = [
        pkgs.bash
        pkgs.coreutils
        pkgs.git
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
      ];
      text = "bash test/release-plan.sh";
    };

    release-consistency = {
      runtimeInputs = [
        pkgs.bash
        pkgs.coreutils
        pkgs.git
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
      ];
      text = ''
        if test "$#" = 0; then
          bash scripts/release/check-version-consistency --mode proposal
        elif test "$#" = 1 && test "$1" = --version; then
          bash scripts/release/get-cabal-version
        else
          bash scripts/release/check-version-consistency "$@"
        fi
      '';
    };

    workflow-lint = {
      runtimeInputs = [
        pkgs.actionlint
        pkgs.bash
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.shellcheck
        pkgs.yq-go
      ];
      text = ''
        set -euo pipefail
        actionlint -config-file .github/actionlint.yaml .github/workflows/*.yml
        shellcheck scripts/release/* test/release-plan.sh

        ci=.github/workflows/ci.yml
        plan=.github/workflows/release-plan.yml
        linux=.github/workflows/release.yml
        darwin=.github/workflows/darwin-release.yml
        pages=.github/workflows/pages.yml

        require_equal() {
          if test "$1" != "$2"; then
            printf 'workflow contract: %s (expected %s, got %s)\n' "$3" "$2" "$1" >&2
            exit 1
          fi
        }
        require_command_line() {
          if ! grep -Fxq "$1" <<<"$2"; then
            printf 'workflow contract: missing %s\n' "$3" >&2
            exit 1
          fi
        }

        require_equal "$(yq -r '(.on.pull_request.branches // []) | join(",")' "$pages")" main 'Pages pull-request main target'
        require_equal "$(yq -r '(.on.pull_request.types // []) | join(",")' "$pages")" opened,synchronize,reopened,closed 'Pages pull-request lifecycle events'
        require_equal "$(yq -r '(.on.pull_request // {}) | has("paths")' "$pages")" false 'Pages pull-request paths filter absence'
        require_equal "$(yq -r '(.on.pull_request // {}) | has("paths-ignore")' "$pages")" false 'Pages pull-request paths-ignore filter absence'
        require_equal "$(yq -r '(.on.push.branches // []) | join(",")' "$pages")" main 'Pages push main target'
        require_equal "$(yq -r '.on | has("workflow_dispatch")' "$pages")" true 'Pages manual dispatch trigger'

        require_equal "$(yq -r '.jobs.build.name // ""' "$pages")" 'Docs build' 'Pages required check name'
        require_equal "$(yq -r '.jobs.build."runs-on" // ""' "$pages")" nixos 'Pages docs-build runner'
        require_equal "$(yq -r '.jobs | to_entries | map(select(.value."runs-on" != "nixos")) | length' "$pages")" 0 'all Pages workflow runners are nixos'
        require_equal "$(yq -r '.jobs.build.if // ""' "$pages")" "github.event_name != 'pull_request' || github.event.action != 'closed'" 'Pages build skips only closed pull requests'
        require_equal "$(yq -r '.jobs.deploy.if // ""' "$pages")" "github.event_name != 'pull_request'" 'Pages deploy excludes pull requests'
        require_equal "$(yq -r '.jobs.cleanup.if // ""' "$pages")" "github.event_name == 'pull_request' && github.event.action == 'closed'" 'Pages cleanup runs on closed pull requests'

        require_equal "$(yq -r '[.jobs[].steps[]? | select(.uses == "actions/checkout@v6")] | length' "$pages")" 1 'Pages checkout v6 action'
        require_equal "$(yq -r '[.jobs[].steps[]? | select(.uses == "cachix/cachix-action@v17")] | length' "$pages")" 1 'Pages Cachix v17 action'
        require_equal "$(yq -r '[.jobs[].steps[]? | select(.uses == "paolino/dev-assets/static-preview@main")] | length' "$pages")" 2 'Pages shared preview publish and cleanup actions'
        require_equal "$(yq -r '[.jobs[].steps[]? | select(.uses == "actions/upload-pages-artifact@v5")] | length' "$pages")" 1 'Pages artifact upload v5 action'
        require_equal "$(yq -r '[.jobs[].steps[]? | select(.uses == "actions/deploy-pages@v5")] | length' "$pages")" 1 'Pages deploy v5 action'

        build_command="$(yq -r '.jobs.build.steps[]? | select(.name == "Build site") | .run' "$pages")"
        require_command_line 'nix build --quiet .#site' "$build_command" 'quiet site build command'
        require_command_line 'cp -R -L result/. site/' "$build_command" 'writable site artifact copy'
        require_command_line 'chmod -R u+w site' "$build_command" 'writable site artifact permissions'
        require_equal "$(yq -r '.jobs.build.steps[]? | select(.uses == "paolino/dev-assets/static-preview@main") | .if // ""' "$pages")" "github.event_name == 'pull_request'" 'Pages preview publish condition'
        require_equal "$(yq -r '.jobs.build.steps[]? | select(.uses == "paolino/dev-assets/static-preview@main") | .with.path // ""' "$pages")" site 'Pages preview source path'
        require_equal "$(yq -r '.jobs.build.steps[]? | select(.uses == "actions/upload-pages-artifact@v5") | .if // ""' "$pages")" "github.event_name != 'pull_request'" 'Pages artifact upload condition'
        require_equal "$(yq -r '.jobs.build.steps[]? | select(.uses == "actions/upload-pages-artifact@v5") | .with.path // ""' "$pages")" site 'Pages upload source path'
        require_equal "$(yq -r '.jobs.cleanup.steps[]? | select(.uses == "paolino/dev-assets/static-preview@main") | .with.mode // ""' "$pages")" cleanup 'Pages preview cleanup mode'
        require_equal "$(yq -r '.jobs.deploy.needs // ""' "$pages")" build 'Pages deploy build dependency'
        require_equal "$(yq -r '.jobs.deploy.environment.name // ""' "$pages")" github-pages 'Pages deployment environment'

        require_equal "$(yq -r '.permissions.contents // ""' "$pages")" read 'Pages contents permission'
        require_equal "$(yq -r '.permissions.pages // ""' "$pages")" write 'Pages deployment permission'
        require_equal "$(yq -r '.permissions."id-token" // ""' "$pages")" write 'Pages identity-token permission'
        require_equal "$(yq -r '.permissions.issues // ""' "$pages")" write 'Pages issue-comment permission'
        require_equal "$(yq -r '.permissions."pull-requests" // ""' "$pages")" write 'Pages pull-request-comment permission'
        require_equal "$(yq -r '.concurrency."cancel-in-progress"' "$pages")" false 'Pages and preview concurrency cancellation policy'

        for obsolete in .github/workflows/sync-cabal-version.yml release-please-config.json .release-please-manifest.json; do
          test ! -e "$obsolete" || { echo "workflow contract: obsolete artifact $obsolete" >&2; exit 1; }
        done
        for file in "$ci" "$plan" "$linux" "$darwin"; do
          if grep -Fq 'release-please' "$file"; then
            echo "workflow contract: stale release planner in $file" >&2
            exit 1
          fi
        done
        grep -Fq 'nix run --quiet .#release-consistency' "$ci"
        if grep -Fq 'run: scripts/release/check-version-consistency --mode proposal' "$ci"; then
          echo 'workflow contract: release consistency must run through the Nix boundary' >&2
          exit 1
        fi
        grep -Fq 'actions/create-github-app-token@v1' "$plan"
        grep -Fq 'repositories: tmux-ws' "$plan"
        # shellcheck disable=SC2016
        grep -Fq 'token: ''${{ steps.app-token.outputs.token }}' "$plan"
        grep -Fq 'scripts/release/plan' "$plan"
        grep -Fq 'FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"' "$plan"
        test "$(yq -r '.on.push.branches | join(",")' "$plan")" = main

        for workflow in "$linux" "$darwin"; do
          test "$(yq -r '.on.pull_request.branches | join(",")' "$workflow")" = main
          test "$(yq -r '.on.push.tags | join(",")' "$workflow")" = 'v*'
          grep -Fq 'workflow_dispatch: {}' "$workflow" || grep -Fq 'workflow_dispatch:' "$workflow"
          grep -Fq "github.event_name == 'push'" "$workflow"
          if grep -Fq 'gh release create' "$workflow" \
            || grep -Fq 'gh release delete' "$workflow" \
            || grep -Fq 'git tag -d' "$workflow"; then
            echo "workflow contract: destructive publication command in $workflow" >&2
            exit 1
          fi
        done
        grep -Fq 'retention-days: 30' "$linux"
        test "$(yq -r '.jobs."build-and-smoke"."runs-on"' "$linux")" = nixos
        grep -Fq 'cachix/cachix-action@v17' "$linux"
        grep -Fq 'name: paolino' "$linux"
        # shellcheck disable=SC2016
        grep -Fq 'authToken: ''${{ secrets.CACHIX_AUTH_TOKEN }}' "$linux"
        if grep -Fq 'cachix/install-nix-action' "$linux"; then
          echo 'workflow contract: hosted-runner Nix installer in Linux release workflow' >&2
          exit 1
        fi
        # shellcheck disable=SC2016
        grep -Fq 'test "''${GITHUB_REF_NAME#v}" = "$(nix run --quiet .#release-consistency -- --version)"' "$linux"
        grep -Fq 'nix run --quiet .#release-consistency -- --mode publish' "$linux"
        grep -Fq 'nix build -L .#linux-release-artifacts' "$linux"
        # shellcheck disable=SC2016
        grep -Fq 'nix run .#linux-artifact-smoke -- --artifacts-dir "$(readlink -f result)" --artifact-version "$(nix run --quiet .#release-consistency -- --version)"' "$linux"
        # shellcheck disable=SC2016
        if grep -Fq '$(scripts/release/get-cabal-version)' "$linux"; then
          echo 'workflow contract: bare Linux release version lookup outside Nix' >&2
          exit 1
        fi
        if grep -Fq 'scripts/release/check-version-consistency --mode publish' "$linux"; then
          echo 'workflow contract: bare Linux publish consistency outside Nix' >&2
          exit 1
        fi
        grep -Fq "gh release upload \"\$TAG\" result/* --clobber" "$linux"
        grep -Fq 'Wait for the planner-created GitHub release' "$darwin"
        grep -Fq "gh release upload \"\$TAG\" \"\$ASSET\" --clobber" "$darwin"
        grep -Fq 'scripts/release/get-cabal-version' "$darwin"
        grep -Fq 'bash scripts/render-homebrew-formulas.sh' "$darwin"
        test "$(yq -r '.jobs."build-and-release"."runs-on"' "$darwin")" = macos-14
        grep -Fq 'cachix/install-nix-action@v30' "$darwin"
      '';
    };

    release-product-name = {
      runtimeInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnutar ];
      text = ''
        set -euo pipefail
        darwin=.github/workflows/darwin-release.yml
        ci=.github/workflows/ci.yml
        # shellcheck disable=SC2016
        for literal in 'bin/tmux-ws' 'tmux-ws-''${VERSION}-aarch64-darwin.tar.gz' 'brew install --formula lambdasistemi/tap/tmux-ws' 'tmux-ws --help'; do
          grep -Fq "$literal" "$darwin"
        done
        if grep -Fq 'class TmuxWs < Formula' "$darwin" \
          || grep -Fq 'class AgentDaemon < Formula' "$darwin"; then
          echo 'release product contract: formulas must remain in the shared renderer' >&2
          exit 1
        fi
        # shellcheck disable=SC2016
        grep -Fq 'brew install --formula "$tap/agent-daemon"' "$ci"
        # shellcheck disable=SC2016
        grep -Fq 'brew install --formula "$tap/tmux-ws"' "$ci"
        proof_root="$(mktemp -d)"
        trap 'rm -rf "$proof_root"' EXIT
        bundle="$proof_root/bundle"
        mkdir -p "$bundle/bin"
        # shellcheck disable=SC2016
        printf '#!%s\nif test "$1" = --help; then echo tmux-ws-help; fi\n' "${pkgs.runtimeShell}" > "$bundle/bin/tmux-ws"
        chmod +x "$bundle/bin/tmux-ws"
        version=0.3.1
        formula_dir="$proof_root/formulas"
        bash scripts/render-homebrew-formulas.sh "$formula_dir" "https://example.invalid/tmux-ws-$version-aarch64-darwin.tar.gz" 0000000000000000000000000000000000000000000000000000000000000000 "$version"
        grep -Fqx 'class TmuxWs < Formula' "$formula_dir/tmux-ws.rb"
        grep -Fqx '    bin.install "bin/tmux-ws"' "$formula_dir/tmux-ws.rb"
        grep -Fqx 'class AgentDaemon < Formula' "$formula_dir/agent-daemon.rb"
        grep -Fqx '  depends_on "tmux-ws"' "$formula_dir/agent-daemon.rb"
      '';
    };

    docs-service-contract = {
      runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];
      text = ''
        set -euo pipefail
        require_file() { test -f "$1" || { printf 'docs/service contract: missing %s\n' "$2" >&2; exit 1; }; }
        require_literal() { grep -Fq "$2" "$1" || { printf 'docs/service contract: missing %s\n' "$3" >&2; exit 1; }; }
        reject_literal() { ! grep -Fq "$2" "$1" || { printf 'docs/service contract: forbidden %s\n' "$3" >&2; exit 1; }; }
        module=nix/module.nix; readme=README.md; docs_index=docs/index.md; installation=docs/installation.md; usage=docs/usage.md; development=docs/development.md; deployment=docs/deployment.md; tailscale=docs/tailscale.md; release_guide=docs/release.md; mkdocs=mkdocs.yml
        require_literal "$module" 'options.services.tmux-ws' 'primary services.tmux-ws module option'
        require_literal "$module" 'systemd.services.tmux-ws' 'primary tmux-ws systemd unit'
        require_literal "$module" '/bin/tmux-ws' 'primary tmux-ws service binary'
        require_literal "$module" 'mkRenamedOptionModule' 'legacy service migration route'
        require_literal "$module" 'default = "/var/lib/agent-daemon"' 'private legacy state allowance'
        require_literal "$module" 'default = "agent-daemon"' 'private legacy account allowance'
        reject_literal "$module" 'systemd.services.agent-daemon' 'legacy primary systemd unit'
        reject_literal "$module" '/bin/agent-daemon' 'legacy primary service binary'
        require_literal "$readme" 'tmux-ws --host' 'README primary command'; reject_literal "$readme" 'agent-daemon' 'README legacy primary text'
        require_literal "$docs_index" 'tmux-ws --host' 'index primary command'; reject_literal "$docs_index" 'agent-daemon' 'index legacy primary text'
        require_literal "$deployment" 'services.tmux-ws' 'deployment primary service configuration'; reject_literal "$deployment" 'systemctl enable --now agent-daemon' 'deployment legacy service command'; reject_literal "$deployment" '/bin/agent-daemon' 'deployment legacy binary command'
        require_literal "$tailscale" 'tmux-ws --host' 'Tailscale primary command'; reject_literal "$tailscale" 'agent-daemon --host' 'Tailscale legacy primary command'
        test -f "$release_guide"
        require_literal "$release_guide" 'brew install lambdasistemi/tap/tmux-ws' 'release Homebrew install command'; require_literal "$release_guide" 'brew update' 'release Homebrew update command'; require_literal "$release_guide" 'brew upgrade tmux-ws' 'release Homebrew upgrade command'; require_literal "$release_guide" 'brew upgrade agent-daemon' 'legacy compatibility-alias upgrade path'; require_literal "$release_guide" 'brew uninstall agent-daemon' 'legacy compatibility-alias removal path'
        # shellcheck disable=SC2016
        require_literal "$release_guide" '`v0.3.0`' 'immutable publication version code span'
        require_literal "$release_guide" 'will not be rewritten or deleted' 'immutable no-rewrite/no-delete promise'; require_literal "$release_guide" 'v0.3.1' 'corrective publication version'; require_literal "$release_guide" 'update the real Homebrew tap' 'corrective tap publication boundary'; require_literal "$release_guide" 'corrective release' 'legacy compatibility duration'; require_literal "$release_guide" 'separately reviewed migration ticket' 'legacy removal policy'
        require_literal "$mkdocs" 'release.md' 'release guide navigation entry'

        require_file "$installation" 'installation guide'
        require_file "$usage" 'touch usage guide'
        require_file "$development" 'development guide'

        require_literal "$readme" 'touch-first' 'README touch-first purpose'
        require_literal "$readme" 'Homebrew' 'README macOS installation route'
        require_literal "$readme" 'AppImage' 'README Linux installation route'
        require_literal "$readme" 'nix develop --quiet' 'README Nix development route'
        require_literal "$readme" 'nix run --quiet .#docs-service-contract' 'README focused verification route'
        require_literal "$readme" 'https://lambdasistemi.github.io/tmux-ws/docs/' 'README stable public documentation link'
        require_literal "$readme" 'https://github.com/lambdasistemi/tmux-ws/releases/latest' 'README stable latest-release link'
        require_literal "$readme" 'MIT' 'README license identifier'

        require_literal "$mkdocs" 'site_url: https://lambdasistemi.github.io/tmux-ws/docs/' 'canonical documentation URL'
        require_literal "$mkdocs" 'repo_url: https://github.com/lambdasistemi/tmux-ws' 'canonical repository URL'
        require_literal "$mkdocs" '  - search' 'Material search plugin'
        for feature in navigation.indexes navigation.sections navigation.path toc.integrate content.code.copy; do
          require_literal "$mkdocs" "    - $feature" "Material $feature feature"
        done
        require_literal "$mkdocs" '    - User:' 'user navigation section'
        require_literal "$mkdocs" '    - Operator:' 'operator navigation section'
        require_literal "$mkdocs" '    - Developer:' 'developer navigation section'
        require_literal "$mkdocs" '        - Installation: installation.md' 'installation navigation target'
        require_literal "$mkdocs" '        - Touch usage: usage.md' 'usage navigation target'
        require_literal "$mkdocs" '        - Development: development.md' 'development navigation target'
        require_literal "$mkdocs" 'media: "(prefers-color-scheme: light)"' 'OS-aware light palette'
        require_literal "$mkdocs" 'media: "(prefers-color-scheme: dark)"' 'OS-aware dark palette'
        require_literal "$mkdocs" 'name: Switch to dark mode' 'manual dark palette toggle'
        require_literal "$mkdocs" 'name: Switch to light mode' 'manual light palette toggle'

        require_literal "$installation" 'v0.4.0 is imminent but not yet published' 'truthful imminent release status'
        require_literal "$installation" 'SHA256SUMS' 'checksum manifest guidance'
        require_literal "$installation" 'sha256sum -c SHA256SUMS --ignore-missing' 'checksum verification command'
        require_literal "$installation" 'tmux-ws-<version>-x86_64-linux.AppImage' 'versioned AppImage route'
        require_literal "$installation" 'tmux-ws.AppImage' 'stable AppImage route'
        require_literal "$installation" 'sudo apt install ./tmux-ws-<version>-x86_64-linux.deb' 'apt installation route'
        require_literal "$installation" 'sudo dnf install ./tmux-ws-<version>-x86_64-linux.rpm' 'dnf installation route'
        require_literal "$installation" 'brew install lambdasistemi/tap/tmux-ws' 'Homebrew installation route'
        require_literal "$installation" 'services.tmux-ws' 'NixOS installation route'
        require_literal "$installation" '## Upgrade' 'installation upgrade procedure'

        require_literal "$usage" 'tablet and small-screen' 'tablet and small-screen orientation'
        require_literal "$usage" 'modifier and arrow command deck' 'modifier and arrow command deck'
        require_literal "$usage" 'literal one-shot **Ctrl-B** prefix' 'literal one-shot Tmux prefix'
        require_literal "$usage" '**Close this pane**' 'close-current pane action'
        require_literal "$usage" '**Close this window**' 'close-current window action'
        require_literal "$usage" 'preview' 'close-current preview step'
        require_literal "$usage" 'confirm' 'close-current confirmation step'
        require_literal "$usage" 'in-app **Refresh**' 'in-app refresh distinction'
        require_literal "$usage" 'hard refresh' 'post-upgrade browser hard refresh'
        require_literal "$usage" 'reconnects' 'terminal reconnect behavior'

        require_literal "$development" 'nix develop --quiet' 'Nix-first development setup'
        require_literal "$development" 'just build' 'development build route'
        require_literal "$development" 'nix run --quiet .#haskell-tests' 'Haskell test route'
        require_literal "$development" 'nix run --quiet .#ui' 'UI test route'
        require_literal "$development" 'nix run --quiet .#formatting' 'format check route'
        require_literal "$development" 'nix run --quiet .#hlint' 'lint route'
        require_literal "$development" 'nix build --quiet --no-link .#docs .#site' 'strict docs and site build route'
        require_literal "$development" 'nix develop --quiet -c just ci' 'full local gate route'

        require_literal "$release_guide" 'v0.4.0 is imminent but not yet published' 'truthful v0.4.0 release status'
        reject_literal "$release_guide" 'Future Linux release artifacts' 'stale future-artifact heading'
        reject_literal "$release_guide" 'This PR' 'PR-boundary release wording'
        require_literal "$release_guide" 'https://github.com/lambdasistemi/tmux-ws/releases/latest' 'stable latest-release link'
        require_literal "$release_guide" 'https://github.com/lambdasistemi/tmux-ws/releases' 'stable releases link'
        require_literal "$release_guide" 'https://lambdasistemi.github.io/tmux-ws/docs/installation/' 'stable installation documentation link'
        require_literal "$release_guide" 'SHA256SUMS' 'release checksum manifest'
        require_literal "$release_guide" 'tmux-ws.AppImage' 'release stable AppImage route'
        require_literal "$release_guide" 'sudo apt install' 'release apt route'
        require_literal "$release_guide" 'sudo dnf install' 'release dnf route'
        require_literal "$release_guide" 'systemctl restart tmux-ws' 'release restart guidance'
        require_literal "$release_guide" 'hard refresh' 'release tablet refresh guidance'
      '';
    };
  };

  mkApp = name:
    { runtimeInputs, text }:
    pkgs.writeShellApplication { inherit name runtimeInputs text; };

  mkCheck = name: spec:
    let app = mkApp name spec;
    in pkgs.runCommand name {
      nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux
        [ pkgs.glibcLocales ];
      LANG = "C.UTF-8";
      LC_ALL = "C.UTF-8";
    } ''
      set -euo pipefail
      cd ${src}
      ${pkgs.lib.getExe app}
      touch "$out"
    '';

  apps = builtins.mapAttrs mkApp scripts;
in {
  haskell-build = mkCheck "haskell-build" scripts.haskell-build;
  haskell-tests = mkCheck "haskell-tests" scripts.haskell-tests;
  formatting = mkCheck "formatting" scripts.formatting;
  hlint = mkCheck "hlint" scripts.hlint;
  cabal-package = mkCheck "cabal-package" scripts.cabal-package;
  ui = mkCheck "ui" scripts.ui;
  release-plan = mkCheck "release-plan" scripts.release-plan;
  workflow-lint = mkCheck "workflow-lint" scripts.workflow-lint;
  release-product-name =
    mkCheck "release-product-name" scripts.release-product-name;
  docs-service-contract =
    mkCheck "docs-service-contract" scripts.docs-service-contract;
  inherit apps;
}
