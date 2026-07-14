#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
git diff --check
nix flake check --no-eval-cache
nix develop --quiet -c cabal build all -O0
nix build .#linux-dev-release-artifacts
version="$(awk '$1 == "version:" { print $2; exit }' tmux-ws.cabal)"
revision="$(git rev-parse --short=7 HEAD)"
if git diff --quiet HEAD; then
  artifact_version="${version}-${revision}"
else
  artifact_version="${version}-${revision}-dirty"
fi
nix run .#linux-artifact-smoke -- \
  --artifacts-dir "$(readlink -f result)" \
  --artifact-version "$artifact_version"
