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

## Finalization

The owner reviews each pair-approved commit, stamps the matching tasks into the
same commit, reruns the gate, pushes to draft PR #101, and keeps the PR body
current. After all slices: run the full gate and finalization audit; verify the
exact PR head's hosted checks; remove `gate.sh` in its final lifecycle commit;
then mark the PR ready. The epic owner alone decides merge and the later new
release. No workflow dispatch, tag push, GitHub Release mutation, or tap
mutation is performed for this ticket.
