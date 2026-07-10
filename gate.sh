#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix develop --quiet -c just CI
nix develop --quiet -c bash -lc 'cd ui && just ci'
