# Plan: reproducible Linux and Cabal-owned releases

## Technical context

`main` currently has a release-please planner in `release.yml`, a manifest,
and a sync-to-Cabal workflow, while the parent contract requires Cabal-owned
versioning. The current Darwin publisher is already non-destructive but only
supports an invoked tag path. The flake provides the Haskell executables on
Linux and Darwin but has no Linux bundle outputs. The production baseline is
the immutable `v0.3.1` GitHub Release, which contains only the existing Darwin
asset and is outside this branch's write scope.

The design follows the flake-owned packaging model. `nix/linux-release.nix`
will stage all Linux files in one derivation; `nix/linux-artifact-smoke.nix`
will be a flake app and inspect extracted artifacts, rather than Nix store
outputs. Workflow YAML selects mode, builds the relevant flake output, runs the
same smoke app, retains review artifacts, and gates publication by tag event.

## Slice 1 — flake-owned Linux packages and installed-artifact smoke

**Owned files**: `flake.nix`, `flake.lock`, `nix/linux-release.nix` (new),
and `nix/linux-artifact-smoke.nix` (new).

1. Establish RED evidence that the Linux artifact outputs and smoke app do not
   exist.
2. Add the pinned NixOS bundlers input and Linux-only wrapped `tmux-ws` package
   with `meta.mainProgram`.
3. Derive the version from `tmux-ws.cabal`; make release output names exact and
   dev output names revision-suffixed.
4. Stage versioned AppImage/DEB/RPM, stable `tmux-ws.AppImage`, and
   `SHA256SUMS`; expose the smoke app.
5. Make the smoke copy/extract AppImage, unpack DEB/RPM, locate `tmux-ws`, and
   prove the offline help surface. Run RED/GREEN, flake evaluation, artifact
   build, smoke, and the temporary full gate.

## Ticket-owner gate extension — package proof at every later slice

After accepting Slice 1, extend the temporary `gate.sh` (owner-owned) with
the exact dev-artifact build and `linux-artifact-smoke` invocation. This keeps
the expensive release-boundary proof in every remaining slice without changing
the merged project gate.

## Slice 2 — Cabal planner and atomic workflow conversion

**Owned files**: `scripts/release/plan` (new),
`scripts/release/get-cabal-version` (new),
`scripts/release/check-version-consistency` (new),
`scripts/release/extract-notes` (new), `test/release-plan.sh` (new),
`.github/workflows/release-plan.yml` (new), `.github/workflows/release.yml`,
`.github/workflows/darwin-release.yml`, `.github/workflows/ci.yml`,
`.github/workflows/sync-cabal-version.yml` (delete),
`release-please-config.json` (delete), `.release-please-manifest.json`
(delete), and `nix/checks.nix` to validate the new workflow contracts.

1. Start with focused planner tests proving Cabal is parsed as the only version
   authority and release-please state is rejected; verify dry-run bump,
   changelog, no-releasable-commit, tag/version, and immutable-release cases.
2. Implement the `release/cabal-release` proposal flow. The planner uses the
   App-authenticated checkout to push its branch/tag, creates one GitHub
   Release from matching changelog notes after its annotated tag, and does not
   delete/recreate historical releases.
3. Atomically remove release-please and its sync path; switch CI and Nix
   workflow contracts to the Cabal planner. Do not leave a committed state
   where two planners can act on `main`.
4. Replace the old main-push `release.yml` with Linux PR/default-manual/tag
   modes. Build and smoke flake artifacts in every mode; upload 30-day review
   artifacts; only tag events attach the staged Linux files to the
   planner-created release idempotently.
5. Rework Darwin into the same build-only PR/default-manual and tag-only
   publication boundary while preserving its canonical archive, scoped App
   tokens, Homebrew update, and tap-qualified install smoke.
6. Update Nix workflow contracts so they reject destructive/recreating release
   commands and prove the exact triggers, action scopes, artifact names,
   retention, modes, and product compatibility. Run focused RED/GREEN,
   actionlint, flake checks, Linux smoke, and the full temporary gate.

## Corrective Slice 2.1 — runner-minimal Cabal consistency invocation

**Owned files**: `.github/workflows/ci.yml`, `nix/checks.nix`, and the
smallest existing release-planner test/helper file needed for a runner-minimal
regression. This corrective slice is required after the hosted Build Gate at
`7fec8c5` showed `scripts/release/get-cabal-version: awk: command not found`.

1. Establish RED evidence for the CI consistency command under a minimal PATH
   without `awk`, tracing the direct workflow invocation to the helper's
   runtime dependency.
2. Run the version-consistency command through an explicit Nix-owned runtime
   (or an equivalently flake-owned declared dependency), so a GitHub runner
   never relies on ambient `awk`; do not weaken or remove the consistency step.
3. Extend the static workflow and focused regression contracts to require the
   protected runtime boundary, then run the full gate and obtain hosted
   exact-head Build Gate proof before resuming documentation.

## Slice 3 — release-facing Linux installation guidance

**Owned file**: `docs/release.md` only.

1. Capture RED evidence that the guide does not yet describe release Linux
   artifact use and the stable AppImage path.
2. Add a compact Linux section with AppImage, DEB, and RPM instructions;
   preserve the existing `tmux-ws` Homebrew guidance, bounded compatibility
   route, and immutable published-v0.3.1 statements.
3. State that PR/default manual runs are build-and-smoke only and that a future
   immutable tag attaches production assets; do not imply this PR publishes.
4. Run strict docs/link checks, focused wording proof, Linux smoke, and the
   full temporary gate.

## Corrective Slice 3.1 — hosted Linux smoke invocation contract

**Owned files**: `.github/workflows/release.yml` and the smallest existing
workflow contract test/check needed to prevent a positional smoke-app
invocation from returning.

1. Reproduce the hosted PR-mode command shape: `nix run
   .#linux-artifact-smoke -- result` is invalid because the smoke app accepts
   only `--artifacts-dir DIR --artifact-version VERSION`.
2. Pass the absolute release artifact directory (the smoke app changes into a
   temporary directory) and Cabal/version-derived artifact version through
   those explicit flags. Preserve the PR/manual build-and-smoke mode and
   tag-only release attachment boundary.
3. Add static or focused workflow-contract coverage for the named invocation,
   then run RED/GREEN, Linux artifact smoke, the restored temporary gate, and
   exact-head hosted CI before finalizing again.

## Corrective Slice 3.2 — NixOS Linux release-runner invariant

**Owned files**: `.github/workflows/release.yml` and the smallest existing
workflow contract check/test needed to prevent a hosted Ubuntu Linux release
job from returning.

1. Establish RED evidence that the Linux release build/smoke job uses
   `ubuntu-latest`, contrary to the repository's NixOS Linux-runner pattern.
2. Use the self-hosted `nixos` runner and its established Nix/Cachix setup for
   the Linux build/smoke job. Preserve the current build-only PR/manual mode,
   tag-only asset attachment, and Darwin's required macOS runner.
3. Add focused static workflow coverage for the runner/setup invariant, then
   run RED/GREEN, the restored temporary gate, and exact-head hosted proof on
   the NixOS runner before finalizing again.

## Finalization

The owner reviews each pair-approved commit, stamps the matching tasks into the
same commit, reruns the gate, pushes to draft PR #101, and keeps the PR body
current. After all slices: run the full gate and finalization audit; verify the
exact PR head's hosted checks; remove `gate.sh` in its final lifecycle commit;
then mark the PR ready. The epic owner alone decides merge and the later new
release. No workflow dispatch, tag push, GitHub Release mutation, or tap
mutation is performed for this ticket.
