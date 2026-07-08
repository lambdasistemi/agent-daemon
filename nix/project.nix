{ pkgs }:
let
  project = pkgs.haskell-nix.cabalProject' {
    src = pkgs.haskell-nix.cleanSourceHaskell {
      src = ./..;
      name = "agent-daemon";
    };
    compiler-nix-name = "ghc984";
    shell = { ... }: {
      tools = {
        cabal = { };
        fourmolu = { };
        hlint = { };
        hoogle = { };
        cabal-fmt = { };
      };
      buildInputs = with pkgs; [
        just
        nixfmt-classic
        shellcheck
        stgit
        tmux
        websocat
        purs
        spago-unstable
        purs-tidy-bin.purs-tidy-0_10_0
        esbuild
        nodejs_22
      ];
    };
  };
  uiNodeModules = pkgs.importNpmLock.buildNodeModules {
    npmRoot = ./../ui;
    nodejs = pkgs.nodejs_22;
  };
  static = pkgs.mkSpagoDerivation {
    pname = "agent-daemon-static";
    version = "0.1.0";
    src = ./../ui;
    spagoYaml = ./../ui/spago.yaml;
    spagoLock = ./../ui/spago.lock;
    nativeBuildInputs = [
      pkgs.purs
      pkgs.spago-unstable
      pkgs.esbuild
      pkgs.nodejs_22
    ];
    buildPhase = ''
      ln -s ${uiNodeModules}/node_modules node_modules
      mkdir -p dist/fonts
      cp node_modules/@xterm/xterm/css/xterm.css dist/xterm.css
      cp node_modules/@fontsource/jetbrains-mono/files/jetbrains-mono-latin-400-normal.woff2 dist/fonts/
      cp node_modules/@fontsource/noto-sans-symbols-2/files/noto-sans-symbols-2-symbols-400-normal.woff2 dist/fonts/
      esbuild src/bootstrap.js \
        --bundle \
        --outfile=dist/deps.js \
        --format=iife \
        --platform=browser \
        --minify
      spago bundle --offline --module Main --outfile dist/app.js
      cat dist/deps.js dist/app.js > dist/index.js
      rm dist/deps.js dist/app.js
    '';
    installPhase = ''
      mkdir -p $out
      cp -r dist/* $out/
    '';
  };
in {
  packages = {
    main = project.hsPkgs.agent-daemon.components.exes.agent-daemon;
    inherit static;
  };
  devShells.default = project.shell;
}
