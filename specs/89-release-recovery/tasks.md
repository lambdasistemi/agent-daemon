# Tasks: rebase-safe release recovery

## Release resolution

- [ ] T001 Add guarded fallback release creation for rebased generated release PRs.
- [ ] T002 Route resolved release outputs to the Darwin publisher and cover the no-op boundaries.

## Darwin bundling

- [ ] T003 Skip staged dylib self install IDs while rejecting unresolved dependencies.

## Publication

- [ ] P001 Merge final-head green PR.
- [ ] P002 Rerun v0.2.0 Darwin publication and verify release asset plus Homebrew smoke.
