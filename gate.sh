#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix flake check --no-eval-cache
nix develop --quiet -c cabal build all -O0
