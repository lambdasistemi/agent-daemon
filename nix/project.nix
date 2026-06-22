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
        haskell-language-server = { };
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
      ];
    };
  };
  static = pkgs.runCommand "agent-daemon-static" { } ''
    mkdir -p $out
    cp -r ${./..}/static/* $out/
  '';
in {
  packages = {
    main = project.hsPkgs.agent-daemon.components.exes.agent-daemon;
    tests = project.hsPkgs.agent-daemon.components.tests.e2e-tests;
    inherit static;
  };
  devShells.default = project.shell;
}
