# Research: tmux-ws release product name

## Canonical package with bounded executable compatibility

Use `tmux-ws` for the Cabal package, Nix default, and primary executable.
Ship `agent-daemon` as a tested compatibility executable that reaches the same
daemon entry point for this patch only. Silent removal breaks scripts; renaming
internal modules or browser keys creates unnecessary state risk.

## Primary and deprecated Homebrew formulas

The tap currently contains only `Formula/agent-daemon.rb` for immutable v0.3.0.
The publisher must generate `Formula/tmux-ws.rb` for the new archive and retain
`Formula/agent-daemon.rb` as an explicit deprecated route to the canonical
formula. The primary smoke is always `brew install lambdasistemi/tap/tmux-ws`.

## Flake-owned source guard plus non-publishing package proof

The flake must reject source regressions of name, archive, formula, docs, and
author selector. A Darwin CI dry-run/equivalent must validate the actual
archive/formula contract without release upload or tap write. `./gate.sh` runs
the complete flake check plus a real development-shell build.

## Exact GitHub App author predicate

The existing selector accepts only `lambdasistemi-ci[bot]`. Accept both that
and `app/lambdasistemi-ci`, retaining merged, main-base, generated-head,
title/version, time, and one-match constraints. Do not broaden to arbitrary
bots or branch-only matching.

## Primary NixOS service with legacy route

Use `services.tmux-ws` and `tmux-ws.service` as the current contract. Retain
the old configuration/service route as an explicitly documented, evaluated
compatibility migration; do not rename private service account/state merely
for product-name consistency.
