#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix run --quiet .#workflow-lint
nix develop --quiet -c just ci
