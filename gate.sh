#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix flake check --no-eval-cache
nix develop --quiet -c cabal build all -O0

release_guide=docs/release.md
! grep -Fq '`v0.3.1` release will publish' "$release_guide"
! grep -Fq 'this PR itself does neither' "$release_guide"
grep -Fq '`v0.3.0` is immutable and remains unchanged' "$release_guide"
grep -Fq '`v0.3.1` is published with the canonical `tmux-ws-0.3.1-aarch64-darwin.tar.gz`' "$release_guide"
grep -Fq 'updated Homebrew tap formula' "$release_guide"
grep -Fq 'reload the browser document on Chrome tablets' "$release_guide"
