{ pkgs, src, components, uiBuild, uiBundle, uiNodeModules }:
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
      runtimeInputs = [ components.tests.e2e-tests pkgs.git pkgs.tmux ];
      text = ''
        export GIT_CONFIG_COUNT=1
        export GIT_CONFIG_KEY_0=init.defaultBranch
        export GIT_CONFIG_VALUE_0=main
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
      runtimeInputs = [ pkgs.actionlint pkgs.shellcheck ];
      text = ''
        actionlint -config-file .github/actionlint.yaml .github/workflows/*.yml
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
