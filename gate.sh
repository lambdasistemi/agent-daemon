#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
git diff --check
nix run --quiet .#release-plan
nix run --quiet .#workflow-lint
nix develop --quiet -c just ci
