# Development

The repository is Nix-first: the flake pins the Haskell, PureScript, Node,
MkDocs, and verification toolchain. Start from the repository root.

## Enter the environment

```bash
nix develop --quiet
```

Inside the shell, build all Cabal components with:

```bash
just build
```

Run the daemon from the flake when checking a local browser flow:

```bash
nix run . -- --host 127.0.0.1 --port 8080 --base-dir /code
```

## Tests

The flake exposes the same strict-path applications used by its sandboxed
checks:

```bash
nix run --quiet .#haskell-tests
nix run --quiet .#ui
```

The Haskell suite starts real tmux processes in an isolated socket directory,
so it exercises the live tmux boundary rather than a mocked command. The UI
route runs the terminal-input tests and, on Linux, the Playwright command-deck
layout test.

## Lint and format checks

```bash
nix run --quiet .#formatting
nix run --quiet .#hlint
nix run --quiet .#cabal-package
```

To apply the repository formatters while inside the development shell, run
`just format`, then rerun the checks above.

## Documentation and combined site

Build the strict MkDocs output and the combined SPA/documentation site:

```bash
nix build --quiet --no-link .#docs .#site
nix run --quiet .#docs-service-contract
```

The docs derivation runs `mkdocs build --strict` followed by internal
link-and-anchor validation. The site derivation places the SPA at `/` and the
documentation at `/docs/`.

For a local authoring server from the development shell:

```bash
just serve-docs
```

## Full local gate

The enduring project-owned CI route enters the development shell, runs every
flake check, and performs the representative Cabal build:

```bash
nix develop --quiet -c just ci
```

Before sending a change for review, also run `git diff --check` and the focused
docs/site build above. For browser-facing changes, serve the built `.#site`
from localhost and open both `/` and `/docs/`; this verifies the live static
site boundary that unit and strict Markdown checks do not cover alone.
