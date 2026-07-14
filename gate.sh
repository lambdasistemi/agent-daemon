#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
git diff --check
nix flake check --no-eval-cache
nix develop --quiet -c cabal build all -O0
