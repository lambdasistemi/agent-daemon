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

- [X] T006-O Extend the temporary gate with dev Linux artifact build and smoke
  after Slice 1 acceptance; verify the new command before committing it.

## Slice 2 — Cabal planner and workflow conversion

- [X] T007-S2 Establish RED proof for Cabal-only version authority, planner
  dry-run/version/changelog rules, and release-please rejection.
- [X] T008-S2 Implement and test the Cabal planner scripts and
  `release/cabal-release` App-token workflow, including immutable annotated
  tag and planner-created release behavior.
- [X] T009-S2 Atomically remove manifest/release-please/sync flow and update
  CI plus Nix workflow contracts for Cabal version consistency.
- [X] T010-S2 Add PR/default-manual build-and-smoke Linux/Darwin modes with
  30-day review artifacts and no external mutation.
- [X] T011-S2 Add tag-only Linux attachment to the existing planner-created
  release, preserving Darwin/Homebrew's scoped, non-destructive publication.
- [X] T012-S2 Green focused planner/workflow RED-GREEN evidence, actionlint,
  flake checks, Linux artifact smoke, and the extended full gate in one
  reviewed commit.

## Corrective Slice 2.1 — runner-minimal CI release consistency

- [X] T013-C1 Establish a RED reproduction of the hosted runner-minimal PATH
  failure and trace the missing `awk` dependency from CI to the release helper.
- [X] T014-C1 Invoke consistency validation through an explicit Nix-owned or
  flake-owned runtime without weakening the validation behavior.
- [X] T015-C1 Add regression/static workflow coverage, pass the extended gate,
  and obtain hosted exact-head Build Gate proof.

## Slice 3 — narrow Linux release guide

- [ ] T016-S3 Establish RED evidence for missing Linux artifact and
  non-publication-boundary guidance.
- [ ] T017-S3 Document the stable AppImage and versioned DEB/RPM routes while
  preserving `tmux-ws` identity, bounded compatibility, and v0.3.1 history.
- [ ] T018-S3 Green focused guide/docs checks, Linux artifact smoke, and the
  extended full gate in one reviewed commit.

## Finalization

- [ ] T019-O Audit all checked tasks, commit messages, PR body, exact
  artifact names, publication/rollback guarantees, local gate, and exact-head
  hosted CI; drop `gate.sh` only when the PR is ready for review.
