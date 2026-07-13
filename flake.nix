{
  description = "tmux-ws browser SPA and tmux session daemon";
  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    dev-assets-mkdocs.url = "github:paolino/dev-assets?dir=mkdocs";
    purescript-overlay = {
      url = "github:paolino/purescript-overlay/fix/remove-nodePackages";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mkSpagoDerivation = {
      url = "github:jeslie0/mkSpagoDerivation";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs@{ self, nixpkgs, flake-utils, haskellNix, dev-assets-mkdocs
    , purescript-overlay, mkSpagoDerivation, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs {
          overlays = [
            haskellNix.overlay
            purescript-overlay.overlays.default
            mkSpagoDerivation.overlays.default
          ];
          inherit system;
        };
        project = import ./nix/project.nix { inherit pkgs; };
        checksWithApps = import ./nix/checks.nix {
          inherit pkgs;
          inherit (project) components;
          uiBuild = project.packages.uiBuild;
          uiNodeModules = project.packages.uiNodeModules;
          uiBundle = project.packages.static;
          src = ./.;
        };
        mkdocsShell = dev-assets-mkdocs.devShells.${system}.default;
        mkdocsPackages = dev-assets-mkdocs.packages.${system};
        docs = pkgs.stdenv.mkDerivation {
          name = "tmux-ws-docs";
          src = ./.;
          buildInputs = [ mkdocsPackages.from-nixpkgs pkgs.python3 ];
          buildPhase = ''
            mkdocs build --strict -d $out
            python3 - "$out" <<'PY'
            from html.parser import HTMLParser
            from pathlib import Path
            from urllib.parse import unquote, urlsplit
            import sys

            root = Path(sys.argv[1])
            failures = []

            class Links(HTMLParser):
                def __init__(self):
                    super().__init__()
                    self.hrefs, self.ids = [], set()
                def handle_starttag(self, tag, attrs):
                    data = dict(attrs)
                    if tag == "a" and data.get("href"):
                        self.hrefs.append(data["href"])
                    if data.get("id"):
                        self.ids.add(data["id"])

            for page in root.rglob("*.html"):
                parser = Links()
                parser.feed(page.read_text())
                for href in parser.hrefs:
                    target = urlsplit(href)
                    if target.scheme or target.netloc or href.startswith("mailto:"):
                        continue
                    path = unquote(target.path)
                    if path.startswith("/tmux-ws/docs/"):
                        path = path.removeprefix("/tmux-ws/docs/")
                    elif path.startswith("/"):
                        continue
                    destination = page if not path else (page.parent / path)
                    if destination.is_dir():
                        destination /= "index.html"
                    elif not destination.suffix:
                        destination = destination / "index.html"
                    if not destination.exists():
                        failures.append(f"{page.relative_to(root)}: missing {href}")
                        continue
                    if target.fragment:
                        target_parser = Links()
                        target_parser.feed(destination.read_text())
                        if target.fragment not in target_parser.ids:
                            failures.append(f"{page.relative_to(root)}: missing anchor {href}")
            if failures:
                raise SystemExit("\n".join(failures))
            PY
          '';
          dontInstall = true;
        };
        site = pkgs.runCommand "tmux-ws-site" { } ''
          mkdir -p $out/docs
          cp -r ${project.packages.static}/* $out/
          cp -r ${docs}/* $out/docs/
        '';
        mkModuleCheck = name: serviceConfig:
          let
            configuration = nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = { inherit self; };
              modules =
                [ (import ./nix/module.nix { inherit self; }) serviceConfig ];
            };
            service = configuration.config.systemd.services."tmux-ws";
            legacyUnit = if builtins.hasAttr "agent-daemon"
            configuration.config.systemd.services then
              "present"
            else
              "absent";
          in pkgs.runCommand name { } ''
            test '${legacyUnit}' = absent
            test '${service.serviceConfig.User}' = agent-daemon
            test '${service.serviceConfig.Group}' = agent-daemon
            test '${service.serviceConfig.WorkingDirectory}' = /var/lib/agent-daemon
            case '${service.serviceConfig.ExecStart}' in
              */bin/tmux-ws\ *) ;;
              *) echo 'module contract: primary unit must execute bin/tmux-ws' >&2; exit 1 ;;
            esac
            touch $out
          '';
      in {
        packages = project.packages // {
          default = project.packages.tmux-ws;
          inherit docs site;
        };
        checks = (builtins.removeAttrs checksWithApps [ "apps" ])
          // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            module-canonical = mkModuleCheck "module-canonical" {
              services.tmux-ws.enable = true;
            };
            module-legacy = mkModuleCheck "module-legacy" {
              services.agent-daemon.enable = true;
            };
          };
        apps = import ./nix/apps.nix {
          inherit pkgs;
          checks = checksWithApps;
          packages = project.packages;
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
