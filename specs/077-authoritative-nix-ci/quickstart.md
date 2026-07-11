# Verification Quickstart

## Focused local checks

```bash
nix run --quiet .#haskell-build
nix run --quiet .#haskell-tests
nix run --quiet .#formatting
nix run --quiet .#hlint
nix run --quiet .#cabal-package
nix run --quiet .#ui
nix run --quiet .#workflow-lint
```

## Complete local contract

```bash
nix flake check --no-eval-cache
nix develop --quiet -c just ci
```

Expected Haskell evidence: `55 examples, 0 failures`.

## Pull-request contract

Inspect pull request #81 and verify every context in `contracts/quality-contract.md` is present and successful. Do not update the ruleset before all names have been observed.

## Ruleset contract

```bash
gh api repos/lambdasistemi/tmux-ws/rulesets/13867328
```

Verify the exact required-context set and repository-role bypass actor `5` after the final update.
