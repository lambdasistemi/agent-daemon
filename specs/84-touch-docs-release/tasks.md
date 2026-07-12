# Tasks: Touch documentation and v0.2.0 release

## Slice 1 — operator documentation

- [X] T001-S1 Document tablet controls, identity, close safety, and refresh/cache semantics.
- [X] T002-S1 Document reboot-persistent NixOS and Tailscale deployment.
- [X] T003-S1 Add system-aware light/dark documentation palettes and build the site.

## Slice 2 — deterministic release automation

- [X] T004-S2 Add manifest-driven release creation and Cabal-version synchronization.
- [X] T005-S2 Repair the Darwin bundle layout, release safety, and Homebrew smoke.
- [X] T006-S2 Add CI version drift and workflow validation coverage.

## Slice 3 — runner-hermetic version preflight

- [X] T010-S3 Remove the CI drift check's dependency on host `awk` and enforce the boundary.

## Slice 4 — preserve feature minor releases

- [ ] T011-S4 Remove pre-1.0 feature-to-patch conversion and enforce the release policy.

## Publication

- [ ] P007 Merge the green implementation PR and verify Pages.
- [ ] P008 Merge the green release PR and verify `v0.2.0` artifacts.
- [ ] P009 Pin and smoke the development service from the released revision.
