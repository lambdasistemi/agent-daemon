{ pkgs, src, components, uiBuild, uiBundle, uiNodeModules, }:
let
  scripts = {
    haskell-build = {
      runtimeInputs = [ components.exes.agent-daemon ];
      text = ''
        test -e ${components.library}
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
        diff -u agent-daemon.cabal <(cabal-fmt agent-daemon.cabal)
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
      runtimeInputs = [ pkgs.purs-tidy-bin.purs-tidy-0_10_0 ];
      text = ''
        test -d ${uiNodeModules}/node_modules
        test -e ${uiBuild}
        test -s ${uiBundle}/index.html
        test -s ${uiBundle}/index.js
        purs-tidy check 'ui/src/**/*.purs'
      '';
    };

    workflow-lint = {
      runtimeInputs = [ pkgs.actionlint pkgs.shellcheck pkgs.yq-go ];
      text = ''
        actionlint -config-file .github/actionlint.yaml .github/workflows/*.yml

        workflow=.github/workflows/ci.yml

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
          'pull_request,push' 'workflow triggers'
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
