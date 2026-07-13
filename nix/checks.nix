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
        export GIT_CONFIG_COUNT=1
        export GIT_CONFIG_KEY_0=init.defaultBranch
        export GIT_CONFIG_VALUE_0=main
        TMUX_TMPDIR="$(mktemp -d)"
        export TMUX_TMPDIR
        trap 'rm -rf "$TMUX_TMPDIR"' EXIT
        SHELL="${pkgs.bashInteractive}/bin/bash"
        export SHELL
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
      text = ''
        cabal check
      '';
    };

    ui = {
      runtimeInputs = [ pkgs.nodejs_22 pkgs.purs-tidy-bin.purs-tidy-0_10_0 ]
        ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux
        [ pkgs.playwright-test ];
      text = ''
        test -d ${uiNodeModules}/node_modules
        test -e ${uiBuild}
        test -s ${uiBundle}/index.html
        test -s ${uiBundle}/index.js
        purs-tidy check 'ui/src/**/*.purs'
        node --test ui/test/TerminalInput.test.mjs
        if [[ "$(uname)" == Linux ]]; then
          export UI_BUNDLE=${uiBundle}
          export NODE_PATH=${pkgs.playwright-test}/lib/node_modules
          export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
          export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
          node --test ui/test/CommandDeckLayout.test.mjs
        fi
      '';
    };

    workflow-lint = {
      runtimeInputs = [
        pkgs.actionlint
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.jq
        pkgs.shellcheck
        pkgs.yq-go
      ];
      text = ''
        actionlint -config-file .github/actionlint.yaml .github/workflows/*.yml

        workflow=.github/workflows/ci.yml
        darwin_workflow=.github/workflows/darwin-release.yml
        release_workflow=.github/workflows/release.yml
        sync_workflow=.github/workflows/sync-cabal-version.yml
        manifest=.release-please-manifest.json
        release_config=release-please-config.json

        assert_eq() {
          local actual="$1"
          local expected="$2"
          local label="$3"

          if [[ "$actual" != "$expected" ]]; then
            printf 'workflow contract: %s: expected %q, got %q\n' \
              "$label" "$expected" "$actual" >&2
            return 1
          fi
        }

        assert_command() {
          local job="$1"
          local command="$2"
          local count

          count="$(
            JOB="$job" COMMAND="$command" yq -r \
              '[.jobs[env(JOB)].steps[] | select(.run == env(COMMAND))] | length' \
              "$workflow"
          )"
          assert_eq "$count" 1 "$job runs $command"
        }

        assert_no_host_parser() {
          local command="$1"
          local label="$2"

          if printf '%s\n' "$command" \
            | grep -Eq '(^|[^[:alnum:]_-])(awk|cut|grep|jq|perl|python[0-9]*|ruby|sed|yq)([^[:alnum:]_-]|$)'; then
            printf 'workflow contract: %s invokes an unprovisioned host parser\n' \
              "$label" >&2
            return 1
          fi
        }

        assert_version_contract() {
          local manifest_path="$1"
          local cabal_path="$2"
          local label="$3"
          local manifest_value
          local cabal_value

          manifest_value="$(
            jq -er '."." | select(
              type == "string" and
              test("^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$")
            )' "$manifest_path"
          )"
          cabal_value="$(awk '$1 == "version:" { print $2; exit }' "$cabal_path")"
          assert_eq "$cabal_value" "$manifest_value" "$label Cabal/manifest equality"
        }

        assert_eq \
          "$(yq -r '.jobs | keys | sort | join(",")' "$workflow")" \
          'build-darwin,build-gate,cabal-package,dev-shell,formatting,haskell,hlint,ui,workflow-lint' \
          'exact job IDs'

        while IFS='|' read -r job name runner; do
          assert_eq \
            "$(JOB="$job" yq -r '.jobs[env(JOB)].name // ""' "$workflow")" \
            "$name" "$job name"
          assert_eq \
            "$(JOB="$job" yq -r '.jobs[env(JOB)]["runs-on"] // ""' "$workflow")" \
            "$runner" "$job runner"
          assert_eq \
            "$(JOB="$job" yq -r \
              '[.jobs[env(JOB)].steps[] | select((.uses // "") | test("^actions/checkout@"))] | length' \
              "$workflow")" \
            1 "$job checkout action count"
          assert_eq \
            "$(JOB="$job" yq -r \
              '.jobs[env(JOB)].steps[] | select((.uses // "") | test("^actions/checkout@")) | .uses' \
              "$workflow")" \
            'actions/checkout@v6' "$job checkout action version"

          if [[ "$runner" == nixos ]]; then
            assert_eq \
              "$(JOB="$job" yq -r \
                '[.jobs[env(JOB)].steps[] | select((.uses // "") | test("^cachix/cachix-action@"))] | length' \
                "$workflow")" \
              1 "$job Cachix action count"
            assert_eq \
              "$(JOB="$job" yq -r \
                '.jobs[env(JOB)].steps[] | select((.uses // "") | test("^cachix/cachix-action@")) | .uses' \
                "$workflow")" \
              'cachix/cachix-action@v17' "$job Cachix action version"
          fi

          if [[ "$job" != build-gate && "$runner" == nixos ]]; then
            assert_eq \
              "$(JOB="$job" yq -r '.jobs[env(JOB)].needs // ""' "$workflow")" \
              'build-gate' "$job dependency"
          fi
        done <<'JOBS'
        build-gate|Build Gate|nixos
        haskell|Haskell build and tests|nixos
        formatting|Formatting|nixos
        hlint|HLint|nixos
        cabal-package|Cabal package validation|nixos
        ui|PureScript UI|nixos
        workflow-lint|Workflow lint|nixos
        dev-shell|Dev shell build|nixos
        build-darwin|Darwin build|macos-14
        JOBS

        assert_eq \
          "$(yq -r '.on | keys | sort | join(",")' "$workflow")" \
          'pull_request,push,workflow_dispatch' 'workflow triggers'
        assert_eq \
          "$(yq -r '.on.push | keys | sort | join(",")' "$workflow")" \
          'branches' 'push trigger keys'
        assert_eq \
          "$(yq -r '.on.push.branches | join(",")' "$workflow")" \
          'main' 'push branches'
        assert_eq \
          "$(yq -r '.on.pull_request | keys | sort | join(",")' "$workflow")" \
          'branches' 'pull request trigger keys'
        assert_eq \
          "$(yq -r '.on.pull_request.branches | join(",")' "$workflow")" \
          'main' 'pull request branches'
        assert_eq \
          "$(yq -r '[.jobs[] | select(has("if"))] | length' "$workflow")" \
          0 'job-level condition count'
        assert_eq \
          "$(yq -r '[.jobs[] | select(has("strategy"))] | length' "$workflow")" \
          0 'job strategy count'
        expected_concurrency='$'"{{ github.workflow }}-"'$'"{{ github.ref }}"
        assert_eq \
          "$(yq -r '.concurrency.group // ""' "$workflow")" \
          "$expected_concurrency" 'concurrency group'
        assert_eq \
          "$(yq -r '.concurrency["cancel-in-progress"] // false' "$workflow")" \
          true 'concurrency cancellation'

        assert_command build-gate 'nix flake check --no-eval-cache'
        assert_command build-gate \
          'nix build --quiet .#devShells.x86_64-linux.default.inputDerivation'
        assert_command haskell 'nix run --quiet .#haskell-build'
        assert_command haskell 'nix run --quiet .#haskell-tests'
        assert_command formatting 'nix run --quiet .#formatting'
        assert_command hlint 'nix run --quiet .#hlint'
        assert_command cabal-package 'nix run --quiet .#cabal-package'
        assert_command ui 'nix run --quiet .#ui'
        assert_command workflow-lint 'nix run --quiet .#workflow-lint'
        assert_command dev-shell \
          'nix develop --quiet -c cabal build all -O0'

        assert_eq \
          "$(yq -r \
            '[.jobs["build-gate"].steps[] | select(.name == "Cabal version matches manifest")] | length' \
            "$workflow")" \
          1 'CI manifest drift guard count'
        version_preflight="$(
          yq -r \
            '.jobs["build-gate"].steps[] | select(.name == "Cabal version matches manifest") | .run' \
            "$workflow"
        )"
        assert_no_host_parser \
          "$version_preflight" \
          'CI manifest drift guard'

        assert_version_contract "$manifest" tmux-ws.cabal current
        future_version_dir="$(mktemp -d)"
        trap 'rm -rf "$future_version_dir"' EXIT
        printf '{".":"0.2.0"}\n' > "$future_version_dir/manifest.json"
        printf 'name: future-version-proof\nversion: 0.2.0\n' \
          > "$future_version_dir/future.cabal"
        assert_version_contract \
          "$future_version_dir/manifest.json" \
          "$future_version_dir/future.cabal" \
          future-0.2.0
        assert_eq \
          "$(jq -r '.packages["."]."release-type"' "$release_config")" \
          simple 'release type'
        assert_eq \
          "$(jq -r '.packages["."]."bump-minor-pre-major"' "$release_config")" \
          true 'pre-major minor bump'
        assert_eq \
          "$(jq -r '.packages["."] | if has("bump-patch-for-minor-pre-major") then ."bump-patch-for-minor-pre-major" == false else true end' "$release_config")" \
          true 'pre-major feature-minor conversion is absent or false'
        assert_eq \
          "$(jq -r 'has("skip-labeling")' "$release_config")" \
          false 'release config omits unsupported skip-labeling property'

        assert_eq \
          "$(yq -r '.on | keys | sort | join(",")' "$release_workflow")" \
          'push,workflow_dispatch' 'release workflow triggers'
        assert_eq \
          "$(yq -r \
            '[.jobs."release-please".steps[] | select(.uses == "actions/create-github-app-token@v3")] | length' \
            "$release_workflow")" \
          1 'release token action version'
        assert_eq \
          "$(yq -r \
            '.jobs."release-please".steps[] | select(.uses == "actions/create-github-app-token@v3") | .with.repositories' \
            "$release_workflow")" \
          tmux-ws 'release token repository scope'
        assert_eq \
          "$(yq -r \
            '.jobs."release-please".steps[] | select(.uses == "actions/create-github-app-token@v3") | .with | with_entries(select(.key | test("^permission-"))) | to_entries | sort_by(.key) | map(.key + "=" + .value) | join(",")' \
            "$release_workflow")" \
          'permission-contents=write,permission-pull-requests=write' \
          'release token least-privilege permissions'
        assert_eq \
          "$(yq -r \
            '[.jobs."release-please".steps[] | select(.uses == "googleapis/release-please-action@v4")] | length' \
            "$release_workflow")" \
          1 'release-please action version'
        assert_eq \
          "$(yq -r \
            '.jobs."release-please".steps[] | select(.uses == "googleapis/release-please-action@v4") | .with."skip-labeling"' \
            "$release_workflow")" \
          true 'release-please action skips labels'
        assert_eq \
          "$(yq -r '.jobs."release-please".outputs.release_created' "$release_workflow")" \
          '$'"{{ steps.resolve.outputs.release_created }}" \
          'release output resolves primary or recovered release'
        assert_eq \
          "$(yq -r '.jobs."release-please".outputs.tag_name' "$release_workflow")" \
          '$'"{{ steps.resolve.outputs.tag_name }}" \
          'release tag resolves primary or recovered release'
        assert_eq \
          "$(yq -r '.jobs."release-please".steps[] | select(.id == "recover") | .if' "$release_workflow")" \
          '$'"{{ github.event_name == 'push' && steps.release.outputs.release_created != 'true' }}" \
          'recovery only follows a non-release main push'
        # shellcheck disable=SC2016
        grep -Fq 'repos/''${GITHUB_REPOSITORY}/commits/''${GITHUB_SHA}/pulls' "$release_workflow"
        grep -Fq 'release-please--branches--main' "$release_workflow"
        grep -Fq '.user.login == "lambdasistemi-ci[bot]"' "$release_workflow"
        grep -Fq '.base.ref == "main"' "$release_workflow"
        grep -Fq 'lambdasistemi-ci[bot]' "$release_workflow"
        # shellcheck disable=SC2016
        grep -Fq 'git ls-remote --exit-code origin "refs/tags/$tag"' "$release_workflow"
        # shellcheck disable=SC2016
        grep -Fq 'repos/''${GITHUB_REPOSITORY}/releases/tags/$tag' "$release_workflow"
        grep -Fq 'release state conflict for %s' "$release_workflow"
        grep -Fq 'release metadata mismatch: generated PR title' "$release_workflow"
        grep -Fq 'release metadata mismatch: Cabal version' "$release_workflow"
        grep -Fq 'release metadata mismatch: changelog section' "$release_workflow"
        grep -Fq 'ambiguous generated release PRs for pushed commit' "$release_workflow"
        grep -Fq 'write_recovery_outputs' "$release_workflow"
        grep -Fq 'Record release recovery start time' "$release_workflow"
        grep -Fq 'RECOVERY_STARTED_AT' "$release_workflow"
        grep -Fq 'gh pr list --state open --head release-please--branches--main' "$release_workflow"
        # shellcheck disable=SC2016
        grep -Fq 'gh pr close "$number" --delete-branch --repo "$GITHUB_REPOSITORY"' "$release_workflow"
        grep -Fq 'warning: could not list false release PRs for cleanup' "$release_workflow"
        grep -Fq 'warning: could not close false release PR %s' "$release_workflow"
        # Assert literal workflow source; expansion would make this weaker.
        # shellcheck disable=SC2016
        grep -Fq 'gh release create "$tag" --target "$GITHUB_SHA"' "$release_workflow"
        assert_eq \
          "$(yq -r '.jobs."publish-darwin".uses' "$release_workflow")" \
          './.github/workflows/darwin-release.yml' 'release calls Darwin publisher'

        assert_eq \
          "$(yq -r '.on | keys | sort | join(",")' "$darwin_workflow")" \
          'workflow_call,workflow_dispatch' 'Darwin recovery triggers'
        assert_eq \
          "$(yq -r '.on.workflow_call.inputs.tag.required' "$darwin_workflow")" \
          true 'called Darwin tag is required'
        assert_eq \
          "$(yq -r '.on.workflow_dispatch.inputs.tag.required' "$darwin_workflow")" \
          true 'manual Darwin tag is required'
        assert_eq \
          "$(yq -r \
            '[.jobs."build-and-release".steps[] | select(.uses == "actions/create-github-app-token@v3")] | length' \
            "$darwin_workflow")" \
          2 'Darwin token action versions'
        assert_eq \
          "$(yq -r \
            '[.jobs."build-and-release".steps[] | select(.uses == "actions/create-github-app-token@v3") | .with.repositories] | sort | join(",")' \
            "$darwin_workflow")" \
          'homebrew-tap,tmux-ws' 'Darwin token repository scopes'
        assert_eq \
          "$(yq -r \
            '[.jobs."build-and-release".steps[] | select(.uses == "actions/create-github-app-token@v3") | .with | with_entries(select(.key | test("^permission-"))) | to_entries | sort_by(.key) | map(.key + "=" + .value) | join(",")] | join(";")' \
            "$darwin_workflow")" \
          'permission-contents=write;permission-contents=write' \
          'Darwin tokens least-privilege permissions'

        if grep -Fq 'gh release delete' "$darwin_workflow"; then
          echo 'workflow contract: destructive release deletion is forbidden' >&2
          exit 1
        fi
        if grep -Fq 'gh release create' "$darwin_workflow"; then
          echo 'workflow contract: Darwin publisher must use an existing release' >&2
          exit 1
        fi
        if grep -Fq 'agent-daemon --help || true' "$darwin_workflow"; then
          echo 'workflow contract: ignored binary smoke is forbidden' >&2
          exit 1
        fi
        grep -Fq 'gh release view' "$darwin_workflow"
        # A copied dylib reports its own @rpath ID in `otool -L`; it is not
        # an unresolved dependency. The executable and every other @ name
        # must continue through the fatal branch.
        # shellcheck disable=SC2016
        grep -Fq 'test "$target" != "$binary"' "$darwin_workflow"
        # shellcheck disable=SC2016
        grep -Fq '@rpath/$(basename "$target")' "$darwin_workflow"
        # Assert literal workflow source; expansion would make this weaker.
        # shellcheck disable=SC2016
        grep -Fq 'gh release upload "$TAG" "$ASSET" --clobber' "$darwin_workflow"
        grep -Fq 'libexec/lib' "$darwin_workflow"
        # Assert literal workflow source; expansion would make this weaker.
        # shellcheck disable=SC2016
        grep -Fq 'codesign --force --sign - "$binary"' "$darwin_workflow"
        grep -Fq 'unstaged Nix dependency remains' "$darwin_workflow"
        # Assert literal workflow source; expansion would make this weaker.
        # shellcheck disable=SC2016
        grep -Fq '"$binary" --help' "$darwin_workflow"
        grep -Fq 'brew trust lambdasistemi/tap' "$darwin_workflow"
        grep -Fq 'agent-daemon --help' "$darwin_workflow"

        assert_eq \
          "$(yq -r \
            '[.jobs.sync.steps[] | select(.uses == "actions/create-github-app-token@v3")] | length' \
            "$sync_workflow")" \
          1 'Cabal sync token action version'
        assert_eq \
          "$(yq -r \
            '.jobs.sync.steps[] | select(.uses == "actions/create-github-app-token@v3") | .with.repositories' \
            "$sync_workflow")" \
          tmux-ws 'Cabal sync token repository scope'
        assert_eq \
          "$(yq -r \
            '.jobs.sync.steps[] | select(.uses == "actions/create-github-app-token@v3") | .with | with_entries(select(.key | test("^permission-"))) | to_entries | sort_by(.key) | map(.key + "=" + .value) | join(",")' \
            "$sync_workflow")" \
          'permission-contents=write' \
          'Cabal sync token least-privilege permissions'
        grep -Fq "startsWith(github.head_ref, 'release-please--')" "$sync_workflow"
        # Assert literal workflow source; expansion would make this weaker.
        # shellcheck disable=SC2016
        grep -Fq 'git push origin "HEAD:''${GITHUB_HEAD_REF}"' "$sync_workflow"
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
  workflow-lint = mkCheck "workflow-lint" scripts.workflow-lint;
  inherit apps;
}
