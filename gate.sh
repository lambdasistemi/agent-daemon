#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix develop --quiet -c just ci
