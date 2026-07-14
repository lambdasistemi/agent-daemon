# Tasks: reproducible Linux and Cabal-owned releases

## Slice 1 — flake-owned Linux packages and smoke

- [X] T001-S1 Establish RED evidence for absent Linux release/dev artifact
  outputs and absent installed-artifact smoke app.
- [X] T002-S1 Add pinned bundlers and a Linux-only canonical `tmux-ws` package
  wrapper carrying `meta.mainProgram`.
- [X] T003-S1 Stage exact release and revision-suffixed dev AppImage/DEB/RPM,
  stable AppImage, and SHA256SUMS outputs from the Cabal version.
- [X] T004-S1 Implement the extraction/install smoke for every format and
  prove offline canonical-executable help behavior.
- [X] T005-S1 Green focused Nix checks, release/dev artifact builds, smoke, and
  the temporary full gate in one reviewed commit.

## Owner gate extension — keep package proof mandatory

- [ ] T006-O Extend the temporary gate with dev Linux artifact build and smoke
  after Slice 1 acceptance; verify the new command before committing it.

## Slice 2 — Cabal planner and workflow conversion

- [ ] T007-S2 Establish RED proof for Cabal-only version authority, planner
  dry-run/version/changelog rules, and release-please rejection.
- [ ] T008-S2 Implement and test the Cabal planner scripts and
  `release/cabal-release` App-token workflow, including immutable annotated
  tag and planner-created release behavior.
- [ ] T009-S2 Atomically remove manifest/release-please/sync flow and update
  CI plus Nix workflow contracts for Cabal version consistency.
- [ ] T010-S2 Add PR/default-manual build-and-smoke Linux/Darwin modes with
  30-day review artifacts and no external mutation.
- [ ] T011-S2 Add tag-only Linux attachment to the existing planner-created
  release, preserving Darwin/Homebrew's scoped, non-destructive publication.
- [ ] T012-S2 Green focused planner/workflow RED-GREEN evidence, actionlint,
  flake checks, Linux artifact smoke, and the extended full gate in one
  reviewed commit.

## Slice 3 — narrow Linux release guide

- [ ] T013-S3 Establish RED evidence for missing Linux artifact and
  non-publication-boundary guidance.
- [ ] T014-S3 Document the stable AppImage and versioned DEB/RPM routes while
  preserving `tmux-ws` identity, bounded compatibility, and v0.3.1 history.
- [ ] T015-S3 Green focused guide/docs checks, Linux artifact smoke, and the
  extended full gate in one reviewed commit.

## Finalization

- [ ] T016-O Audit all checked tasks, commit messages, PR body, exact
  artifact names, publication/rollback guarantees, local gate, and exact-head
  hosted CI; drop `gate.sh` only when the PR is ready for review.
