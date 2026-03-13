# shellcheck shell=bash

set unstable := true

# List available recipes
default:
    @just --list

# Format all source files
format:
    #!/usr/bin/env bash
    set -euo pipefail
    for i in {1..3}; do
        fourmolu -i src app
    done
    cabal-fmt -i *.cabal
    nixfmt *.nix nix/*.nix

# Check formatting without modifying
format-check:
    #!/usr/bin/env bash
    set -euo pipefail
    fourmolu -m check src app
    cabal-fmt -c *.cabal

# Run hlint
hlint:
    #!/usr/bin/env bash
    hlint src app

# Build all components
build:
    #!/usr/bin/env bash
    cabal build all -O0

# Full CI pipeline
CI:
    #!/usr/bin/env bash
    set -euo pipefail
    just build
    fourmolu -m check src app
    hlint src app
