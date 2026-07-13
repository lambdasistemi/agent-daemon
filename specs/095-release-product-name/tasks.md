# Tasks: tmux-ws public release identity

**Input**: [spec.md](./spec.md), [plan.md](./plan.md),
[research.md](./research.md), and [release-surface contract](./contracts/release-surfaces.md)

**Tests**: Every story requires strict RED → GREEN evidence. Each accepted
slice is one bisect-safe commit with the listed `Tasks:` trailer; its checked
tasks are amended into that same commit.

## Phase 1: User Story 1 — Install the named product (P1)

**Goal**: Make `tmux-ws` default while retaining a tested, explicitly
non-primary `agent-daemon` command.

**Independent Test**: Baseline focused check fails for the old default; the
Green packaged output runs both help commands and selects `tmux-ws` as primary.

- [ ] T001 [US1] Add RED public-package and packaged-help assertions in `nix/checks.nix` that fail against the `agent-daemon` default surface.
- [ ] T002 [US1] Rename the public Cabal manifest/package and make `tmux-ws` the default executable in `tmux-ws.cabal`, `nix/project.nix`, and `nix/apps.nix`, retaining a documented compatibility `agent-daemon` executable.
- [ ] T003 [US1] Green the focused package check and update `nix/checks.nix` to prove both commands while selecting `tmux-ws` as primary.

## Phase 2: User Story 2 — Receive a safe macOS/Homebrew corrective release (P1)

**Goal**: Prepare canonical Darwin archive/formula publication and exact App
author recovery without PR-side publication.

**Independent Test**: Baseline name/recovery assertions fail; non-publishing
proof verifies canonical archive/formula/smoke and accepted authors, while
false authors remain rejected.

- [ ] T004 [US2] Add RED archive/formula/author-selector checks in `nix/checks.nix`, including positive and negative GitHub App author examples.
- [ ] T005 [US2] Update `.github/workflows/darwin-release.yml` to generate the canonical `tmux-ws` archive and Homebrew formula plus a deprecated legacy formula route, retaining tag-only publication and existing hardening.
- [ ] T006 [US2] Update `.github/workflows/release.yml`, `.github/workflows/sync-cabal-version.yml` if manifest rename requires it, and `nix/checks.nix` so recovery accepts exactly both App forms and a non-publishing Darwin/Homebrew smoke is required.

## Phase 3: User Story 3 — Follow current installation and service documentation (P2)

**Goal**: Lead current operator material with `tmux-ws` while preserving a
clear, tested service and command migration path.

**Independent Test**: Current-surface guard is RED on old guidance; Green
strict docs/link proof and NixOS compatibility evaluation permit historical
text only in migration material.

- [ ] T007 [US3] Add a RED current-title/install-command and strict documentation/link contract in `nix/checks.nix` and `flake.nix` only if strict docs wiring requires it.
- [ ] T008 [US3] Make `nix/module.nix` expose `tmux-ws` as primary NixOS service while evaluating and documenting the legacy `agent-daemon` migration/alias without renaming private state.
- [ ] T009 [US3] Update `README.md`, `docs/index.md`, `docs/deployment.md`, `docs/tailscale.md`, new `docs/release.md`, and `mkdocs.yml` so new installation, upgrade, deployment, Tailscale, release, and operator commands lead with `tmux-ws` and isolate legacy instructions in migration guidance.
- [ ] T010 [US3] Green the naming guard, strict docs/link proof, NixOS compatibility proof, and focused release/product-name check.

## Dependencies & Execution Order

1. Slice 1 (T001–T003) establishes the canonical package name consumed by all
   later release and docs work.
2. Slice 2 (T004–T006) follows because archive/formula generation consumes the
   canonical package executable.
3. Slice 3 (T007–T010) follows the stable package/formula/service terms.

No slices run in parallel: all deliberately edit `nix/checks.nix`. A
driver/navigator pair handles each in order; the navigator vetoes missing RED
evidence, out-of-scope renames, publish attempts, or missing task trailer.
