{
  description = "WebSocket daemon for managing Claude Code agent sessions";
  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    dev-assets-mkdocs.url = "github:paolino/dev-assets?dir=mkdocs";
  };
  outputs =
    inputs@{ self, nixpkgs, flake-utils, haskellNix, dev-assets-mkdocs, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs {
          overlays = [ haskellNix.overlay ];
          inherit system;
        };
        project = import ./nix/project.nix { inherit pkgs; };
        mkdocsShell = dev-assets-mkdocs.devShells.${system}.default;
        mkdocsPackages = dev-assets-mkdocs.packages.${system};
        docs = pkgs.stdenv.mkDerivation {
          name = "agent-daemon-docs";
          src = ./.;
          buildInputs = [ mkdocsPackages.from-nixpkgs ];
          buildPhase = ''
            mkdocs build -d $out
          '';
          dontInstall = true;
        };
        site = pkgs.runCommand "agent-daemon-site" { } ''
          mkdir -p $out/docs
          cp -r ${./static}/* $out/
          cp -r ${docs}/* $out/docs/
        '';
      in {
        packages = project.packages // {
          default = project.packages.main;
          inherit docs site;
        };
        devShells.default = project.devShells.default.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ])
            ++ (mkdocsShell.nativeBuildInputs or [ ])
            ++ (mkdocsShell.buildInputs or [ ]);
        });
      }) // {
        nixosModules.default = import ./nix/module.nix { inherit self; };
      };
}
