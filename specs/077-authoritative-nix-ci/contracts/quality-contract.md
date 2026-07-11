# Executable Quality Contract

## Local and flake surfaces

| Surface | Flake check/app | Required evidence |
|---|---|---|
| Haskell build | `haskell-build` | Existing library/executable builds and executable smoke succeeds |
| Haskell tests | `haskell-tests` | 55 examples, 0 failures |
| Formatting | `formatting` | Fourmolu, Cabal formatting, and Nix formatting checks succeed |
| HLint | `hlint` | Zero HLint findings |
| Cabal package | `cabal-package` | `cabal check` emits no warnings/errors |
| PureScript UI | `ui` | Lockfile install realization, lint, build, and bundle outputs succeed |
| Workflow lint | `workflow-lint` | All workflow actionlint/shellcheck and structural CI assertions succeed |
| Canonical local gate | `nix develop --quiet -c just ci` | All flake checks plus real dev-shell `cabal build all -O0` succeed |

## GitHub Actions contexts

| Job ID | Required context | Runner | Orchestration command |
|---|---|---|---|
| `build-gate` | `Build Gate` | `nixos` | Realize all Linux checks/apps and dev-shell input derivation |
| `haskell` | `Haskell build and tests` | `nixos` | Run `haskell-build` and `haskell-tests` apps |
| `formatting` | `Formatting` | `nixos` | Run `formatting` app |
| `hlint` | `HLint` | `nixos` | Run `hlint` app |
| `cabal-package` | `Cabal package validation` | `nixos` | Run `cabal-package` app |
| `ui` | `PureScript UI` | `nixos` | Run `ui` app |
| `workflow-lint` | `Workflow lint` | `nixos` | Run `workflow-lint` app |
| `dev-shell` | `Dev shell build` | `nixos` | `nix develop --quiet -c cabal build all -O0` |
| `build-darwin` | `Darwin build` | `macos-14` | Retained `nix build` platform verification |

The ruleset context set equals the second column exactly. Pages and manual release workflows are excluded because they are not always-present pull-request gates.
