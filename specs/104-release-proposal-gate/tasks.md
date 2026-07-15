# Tasks: Version-independent release-plan validation

## Slice 1 — Decouple release-plan validation from the checkout version

- [X] T104 Capture RED on exact PR #102 head `4b9cc627a9d503a81aa6ea394a393b2a791ce529` with the unchanged test and preserve the expected fixed-version failure evidence.
- [X] T105 Derive the live expectation from `tmux-ws.cabal`, declare explicit fixture baseline/release versions, and normalize the synthetic repository in `test/release-plan.sh` only.
- [X] T106 Capture GREEN on the issue branch and an equivalent detached proposal-version tree with the focused Bash, Nix release-plan, and workflow-lint checks.
- [X] T107 Pass `./gate.sh` and return one reviewed Conventional Commit with a non-empty body and `Tasks: T104, T105, T106, T107` trailer.
