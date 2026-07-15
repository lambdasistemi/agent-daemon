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

- [X] T016-S3 Establish RED evidence for missing Linux artifact and
  non-publication-boundary guidance.
- [X] T017-S3 Document the stable AppImage and versioned DEB/RPM routes while
  preserving `tmux-ws` identity, bounded compatibility, and v0.3.1 history.
- [X] T018-S3 Green focused guide/docs checks, Linux artifact smoke, and the
  extended full gate in one reviewed commit.

## Corrective Slice 3.1 — hosted Linux smoke invocation contract

- [X] T019-C2 Establish RED evidence that the PR-mode release workflow's
  positional `linux-artifact-smoke -- result` invocation is rejected by the
  app's named-option contract.
- [X] T020-C2 Correct the Linux workflow to derive and pass the absolute
  artifact directory and version through the smoke app's explicit interface,
  without changing build-only or tag-only publication boundaries.
- [X] T021-C2 Add a focused workflow-contract regression and green local
  checks, artifact smoke, full temporary gate, and hosted exact-head proof.

## Corrective Slice 3.2 — NixOS Linux release-runner invariant

- [X] T022-C3 Establish RED evidence that the Linux release build/smoke job
  uses GitHub-hosted Ubuntu instead of the required self-hosted NixOS runner.
- [X] T023-C3 Correct the Linux release job to use the established NixOS
  runner/setup without changing build-only or tag-only publication boundaries.
- [X] T024-C3 Add a focused runner-contract regression, pass the restored gate,
  and obtain exact-head hosted Linux proof on the NixOS runner.

## Corrective Slice 3.3 — Nix-owned Linux smoke version lookup

- [X] T025-C4 Establish RED evidence that the NixOS-hosted smoke command uses
  the bare runner `get-cabal-version` helper and fails without ambient `awk`.
- [X] T026-C4 Derive the artifact version and tag-only publish consistency
  validation through Nix-owned runtime closures without changing the
  NixOS/Cachix, publication, or Darwin boundaries.
- [X] T027-C4 Add focused workflow-contract coverage, pass the restored gate,
  and obtain fresh exact-head hosted NixOS smoke proof.

## Finalization

- [X] T028-O Audit all checked tasks, commit messages, PR body, exact
  artifact names, publication/rollback guarantees, local gate, and exact-head
  hosted CI; drop `gate.sh` only when the PR is ready for review.
