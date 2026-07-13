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
        dollar='$'

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
        grep -Fq 'tmux-ws.cabal' "$darwin_workflow"
        grep -Fq "tmux-ws-$dollar{VERSION}-aarch64-darwin.tar.gz" "$darwin_workflow"
        grep -Fq 'bin/tmux-ws' "$darwin_workflow"
        grep -Fq 'bash scripts/render-homebrew-formulas.sh' "$darwin_workflow"
        grep -Fq 'Formula/tmux-ws.rb' "$darwin_workflow"
        grep -Fq 'brew install --formula lambdasistemi/tap/tmux-ws' "$darwin_workflow"
        grep -Fq 'tmux-ws --help' "$darwin_workflow"
        if grep -Fq 'class TmuxWs < Formula' "$darwin_workflow" \
          || grep -Fq 'class AgentDaemon < Formula' "$darwin_workflow"; then
          echo 'workflow contract: Darwin formula semantics must live in the shared renderer' >&2
          exit 1
        fi
        if grep -Fq 'bin.write_exec_script Formula["tmux-ws"].opt_bin/"tmux-ws"' "$darwin_workflow"; then
          echo 'workflow contract: legacy formula must not install a conflicting wrapper' >&2
          exit 1
        fi

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

    release-product-name = {
      runtimeInputs =
        [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnutar pkgs.jq ];
      text = ''
        set -euo pipefail

        darwin_workflow=.github/workflows/darwin-release.yml
        release_workflow=.github/workflows/release.yml
        sync_workflow=.github/workflows/sync-cabal-version.yml
        ci_workflow=.github/workflows/ci.yml
        renderer=scripts/render-homebrew-formulas.sh
        dollar='$'
        failures=0

        require_literal() {
          local file="$1"
          local literal="$2"
          local label="$3"

          if ! grep -Fq "$literal" "$file"; then
            printf 'release product contract: missing %s\n' "$label" >&2
            failures=1
          fi
        }

        reject_literal() {
          local file="$1"
          local literal="$2"
          local label="$3"

          if grep -Fq "$literal" "$file"; then
            printf 'release product contract: forbidden %s\n' "$label" >&2
            failures=1
          fi
        }

        require_literal "$darwin_workflow" 'tmux-ws.cabal' 'Darwin tmux-ws Cabal manifest'
        require_literal "$darwin_workflow" 'bin/tmux-ws' 'Darwin primary binary'
        require_literal "$darwin_workflow" "tmux-ws-$dollar{VERSION}-aarch64-darwin.tar.gz" 'Darwin primary archive'
        require_literal "$darwin_workflow" 'bash scripts/render-homebrew-formulas.sh' 'Darwin shared Homebrew renderer invocation'
        require_literal "$darwin_workflow" 'brew install --formula lambdasistemi/tap/tmux-ws' 'primary Homebrew install'
        require_literal "$darwin_workflow" 'tmux-ws --help' 'primary Homebrew smoke'
        reject_literal "$darwin_workflow" 'class TmuxWs < Formula' 'inline primary Homebrew formula semantics'
        reject_literal "$darwin_workflow" 'class AgentDaemon < Formula' 'inline legacy Homebrew formula semantics'
        reject_literal "$darwin_workflow" 'bin.write_exec_script Formula["tmux-ws"].opt_bin/"tmux-ws"' 'legacy formula conflicting wrapper'
        require_literal "$release_workflow" '.user.login == "app/lambdasistemi-ci"' 'recovery App author identity'
        require_literal "$release_workflow" '.author.login == "app/lambdasistemi-ci"' 'cleanup App author identity'
        require_literal "$release_workflow" 'tmux-ws.cabal' 'release recovery Cabal manifest'
        require_literal "$sync_workflow" 'tmux-ws.cabal' 'sync Cabal manifest'
        require_literal "$ci_workflow" './tmux-ws.cabal' 'CI Cabal manifest'
        # Assert literal workflow source; expansion would make this weaker.
        # shellcheck disable=SC2016
        require_literal "$ci_workflow" 'brew tap-new "$tap"' 'temporary local Git tap registration'
        # Assert literal workflow source; expansion would make this weaker.
        # shellcheck disable=SC2016
        require_literal "$ci_workflow" 'brew install --formula "$tap/agent-daemon"' 'temporary local-tap legacy formula install'
        # Assert literal workflow source; expansion would make this weaker.
        # shellcheck disable=SC2016
        require_literal "$ci_workflow" 'brew install --formula "$tap/tmux-ws"' 'temporary local-tap primary formula install'
        require_literal "$ci_workflow" 'tmux-ws --help' 'temporary local-tap primary formula smoke'
        require_literal "$ci_workflow" 'agent-daemon --help' 'temporary local-tap legacy formula smoke'
        # Assert literal workflow source; expansion would make this weaker.
        # shellcheck disable=SC2016
        require_literal "$ci_workflow" 'test ! -e "$agent_daemon_prefix/bin/tmux-ws"' 'legacy keg collision absence'
        require_literal "$ci_workflow" "stat -L -f '%d:%i' \"\$agent_daemon_link\"" 'legacy forwarder resolved identity'
        require_literal "$ci_workflow" "stat -L -f '%d:%i' \"\$tmux_ws_link\"" 'primary binary resolved identity'
        require_literal "$ci_workflow" "test \"\$agent_daemon_identity\" = \"\$tmux_ws_identity\"" 'legacy forwarder resolves to primary binary'

        assert_selector() {
          local selector="$1"
          local payload="$2"
          local expected="$3"
          local label="$4"
          local actual

          actual="$(printf '%s\n' "$payload" | jq -r "$selector")"
          if test "$actual" != "$expected"; then
            printf 'release product contract: %s: expected %s, got %s\n' \
              "$label" "$expected" "$actual" >&2
            failures=1
          fi
        }

        recovery_selector='if (.user.login == "lambdasistemi-ci[bot]" or .user.login == "app/lambdasistemi-ci") then "accepted" else "rejected" end'
        cleanup_selector='if (.author.login == "lambdasistemi-ci[bot]" or .author.login == "app/lambdasistemi-ci") then "accepted" else "rejected" end'
        assert_selector "$recovery_selector" '{"user":{"login":"lambdasistemi-ci[bot]"}}' accepted 'recovery bot author'
        assert_selector "$recovery_selector" '{"user":{"login":"app/lambdasistemi-ci"}}' accepted 'recovery App author'
        assert_selector "$recovery_selector" '{"user":{"login":"unrelated-ci[bot]"}}' rejected 'recovery unrelated bot'
        assert_selector "$cleanup_selector" '{"author":{"login":"lambdasistemi-ci[bot]"}}' accepted 'cleanup bot author'
        assert_selector "$cleanup_selector" '{"author":{"login":"app/lambdasistemi-ci"}}' accepted 'cleanup App author'
        assert_selector "$cleanup_selector" '{"author":{"login":"unrelated-ci[bot]"}}' rejected 'cleanup unrelated bot'

        proof_root="$(mktemp -d)"
        trap 'rm -rf "$proof_root"' EXIT
        bundle="$proof_root/bundle"
        mkdir -p "$bundle/bin"
        cat > "$bundle/bin/tmux-ws" <<'EOF'
        #!${pkgs.runtimeShell}
        if test "$1" = --help; then
          echo 'tmux-ws help'
        fi
        EOF
        chmod +x "$bundle/bin/tmux-ws"

        version=0.3.1
        archive="$proof_root/tmux-ws-$version-aarch64-darwin.tar.gz"
        tar -C "$bundle" -czf "$archive" .
        test -f "$archive"
        tar -tzf "$archive" | grep -Fx './bin/tmux-ws' >/dev/null
        mkdir "$proof_root/extract"
        tar -C "$proof_root/extract" -xzf "$archive"
        "$proof_root/extract/bin/tmux-ws" --help >/dev/null

        formula_dir="$proof_root/formulas"
        bash "$renderer" \
          "$formula_dir" \
          "https://example.invalid/tmux-ws-$version-aarch64-darwin.tar.gz" \
          0000000000000000000000000000000000000000000000000000000000000000 \
          "$version"
        formula="$formula_dir/tmux-ws.rb"
        grep -Fqx 'class TmuxWs < Formula' "$formula"
        grep -Fqx "  url \"https://example.invalid/tmux-ws-$version-aarch64-darwin.tar.gz\"" "$formula"
        grep -Fqx '  sha256 "0000000000000000000000000000000000000000000000000000000000000000"' "$formula"
        grep -Fqx "  version \"$version\"" "$formula"
        grep -Fqx '    bin.install "bin/tmux-ws"' "$formula"
        grep -Fqx '    system "#{bin}/tmux-ws", "--help"' "$formula"

        legacy_formula="$formula_dir/agent-daemon.rb"
        grep -Fqx 'class AgentDaemon < Formula' "$legacy_formula"
        grep -Fqx "  url \"https://example.invalid/tmux-ws-$version-aarch64-darwin.tar.gz\"" "$legacy_formula"
        grep -Fqx '  sha256 "0000000000000000000000000000000000000000000000000000000000000000"' "$legacy_formula"
        grep -Fqx "  version \"$version\"" "$legacy_formula"
        grep -Fqx '  depends_on "tmux-ws"' "$legacy_formula"
        grep -Fqx '    bin.install_symlink Formula["tmux-ws"].opt_bin/"tmux-ws" => "agent-daemon"' "$legacy_formula"
        grep -Fqx '      agent-daemon is deprecated; use tmux-ws.' "$legacy_formula"
        if grep -Fq 'bin.install "bin/tmux-ws"' "$legacy_formula"; then
          printf 'release product contract: legacy formula installs a conflicting tmux-ws binary\n' >&2
          failures=1
        fi
        if grep -Fq 'bin.write_exec_script Formula["tmux-ws"].opt_bin/"tmux-ws"' "$legacy_formula"; then
          printf 'release product contract: legacy formula has a conflicting wrapper\n' >&2
          failures=1
        fi

        if test "$failures" -ne 0; then
          exit 1
        fi
      '';
    };

    docs-service-contract = {
      runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];
      text = ''
        set -euo pipefail

        module=nix/module.nix
        readme=README.md
        docs_index=docs/index.md
        deployment=docs/deployment.md
        tailscale=docs/tailscale.md
        release_guide=docs/release.md
        mkdocs=mkdocs.yml
        failures=0

        require_literal() {
          local file="$1"
          local literal="$2"
          local label="$3"

          if ! grep -Fq "$literal" "$file"; then
            printf 'docs/service contract: missing %s\n' "$label" >&2
            failures=1
          fi
        }

        require_file() {
          local file="$1"
          local label="$2"

          if ! test -f "$file"; then
            printf 'docs/service contract: missing %s\n' "$label" >&2
            failures=1
          fi
        }

        reject_literal() {
          local file="$1"
          local literal="$2"
          local label="$3"

          if grep -Fq "$literal" "$file"; then
            printf 'docs/service contract: forbidden %s\n' "$label" >&2
            failures=1
          fi
        }

        require_literal "$module" 'options.services.tmux-ws' 'primary services.tmux-ws module option'
        require_literal "$module" 'systemd.services.tmux-ws' 'primary tmux-ws systemd unit'
        require_literal "$module" '/bin/tmux-ws' 'primary tmux-ws service binary'
        require_literal "$module" 'mkRenamedOptionModule' 'legacy service migration route'
        require_literal "$module" 'default = "/var/lib/agent-daemon"' 'private legacy state allowance'
        require_literal "$module" 'default = "agent-daemon"' 'private legacy account allowance'
        reject_literal "$module" 'systemd.services.agent-daemon' 'legacy primary systemd unit'
        reject_literal "$module" '/bin/agent-daemon' 'legacy primary service binary'
        require_literal "$readme" 'tmux-ws --host' 'README primary command'
        reject_literal "$readme" 'agent-daemon' 'README legacy primary text'
        require_literal "$docs_index" 'tmux-ws --host' 'index primary command'
        reject_literal "$docs_index" 'agent-daemon' 'index legacy primary text'
        require_literal "$deployment" 'services.tmux-ws' 'deployment primary service configuration'
        reject_literal "$deployment" 'systemctl enable --now agent-daemon' 'deployment legacy service command'
        reject_literal "$deployment" '/bin/agent-daemon' 'deployment legacy binary command'
        require_literal "$tailscale" 'tmux-ws --host' 'Tailscale primary command'
        reject_literal "$tailscale" 'agent-daemon --host' 'Tailscale legacy primary command'
        require_file "$release_guide" 'release operator guide'
        if test -f "$release_guide"; then
        require_literal "$release_guide" 'brew install lambdasistemi/tap/tmux-ws' 'release Homebrew install command'
          require_literal "$release_guide" 'brew update' 'release Homebrew update command'
          require_literal "$release_guide" 'brew upgrade tmux-ws' 'release Homebrew upgrade command'
          require_literal "$release_guide" 'brew upgrade agent-daemon' 'legacy compatibility-alias upgrade path'
          require_literal "$release_guide" 'brew uninstall agent-daemon' 'legacy compatibility-alias removal path'
          # Assert the Markdown code span and publication promise independently.
          # shellcheck disable=SC2016
          require_literal "$release_guide" '`v0.3.0`' 'immutable publication version code span'
          require_literal "$release_guide" 'will not be rewritten or deleted' 'immutable no-rewrite/no-delete promise'
          require_literal "$release_guide" 'v0.3.1' 'corrective publication version'
          require_literal "$release_guide" 'update the real Homebrew tap' 'corrective tap publication boundary'
          require_literal "$release_guide" 'corrective release' 'legacy compatibility duration'
          require_literal "$release_guide" 'separately reviewed migration ticket' 'legacy removal policy'
        fi
        require_literal "$mkdocs" 'release.md' 'release guide navigation entry'

        if test "$failures" -ne 0; then
          exit 1
        fi
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
  release-product-name =
    mkCheck "release-product-name" scripts.release-product-name;
  docs-service-contract =
    mkCheck "docs-service-contract" scripts.docs-service-contract;
  inherit apps;
}
