# Tasks: Authoritative Nix and CI Quality Contract

**Input**: Design documents from `specs/077-authoritative-nix-ci/`
**Prerequisites**: [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [quality contract](./contracts/quality-contract.md)

**Execution model**: Slices 1 and 2 are each executed by the paired bottom-row driver and navigator. Slice 3 is explicitly ticket-orchestrator-owned. Each implementation slice is one bisect-safe commit; the driver never pushes.

## Slice 1: Authoritative Local and Flake Contract

**Goal**: Make every local quality surface a real sandboxed flake check with a matching app, repair Cabal portability without weakening development warnings, and make lowercase `just ci` the complete gate.

**Independent Test**: A deliberate Cabal formatting defect makes `nix run --quiet .#formatting` fail; after restoration, `./gate.sh` exits `0`, Cabal validation is warning-free, all seven focused apps pass, and Haskell reports 55 examples with 0 failures.

**Owned files**: `flake.nix`, `nix/project.nix`, `nix/checks.nix`, `nix/apps.nix`, `justfile`, `agent-daemon.cabal`, `cabal.project`, `.github/actionlint.yaml`, `.github/workflows/darwin-release.yml`.

**Forbidden scope**: Application, test, or UI source; `.github/workflows/ci.yml`; Pages/release behavior; GHC/input upgrades; specs, `gate.sh`, PR metadata, and ruleset state.

- [X] T001 [US1] Move `-Werror` behind manual default-off `development-warnings` in `agent-daemon.cabal`, enable it explicitly in `nix/project.nix`, and edit `cabal.project` only if fresh validation exposes a concrete warning.
- [X] T002 [US1] Create strict-path app specifications and real sandboxed checks in `nix/checks.nix`, project matching apps through `nix/apps.nix`, and wire both from `flake.nix`.
- [X] T003 [US1] Add canonical lowercase `ci` and uppercase compatibility alias `CI` in `justfile` so the full flake gate plus real dev-shell build are covered.
- [X] T004 [P] [US2] Declare custom runner `nixos` in `.github/actionlint.yaml` and make only behavior-neutral shellcheck corrections in `.github/workflows/darwin-release.yml`.
- [X] T005 [US1] Record deliberate RED then restored GREEN formatting-check evidence in ignored `WIP.md` and paired runtime handoffs without leaving the representative defect in `agent-daemon.cabal`.
- [X] T006 [US1] Record warning-free Cabal validation, seven focused app/check results, 55 examples with 0 failures, repository-wide workflow lint, and final `./gate.sh` exit `0` in ignored `WIP.md` before commit.

**Commit**: `ci: make Nix checks authoritative`

**Trailer**: `Tasks: T001, T002, T003, T004, T005, T006`

---

## Slice 2: Stable GitHub Actions Orchestration

**Goal**: Make the pull-request workflow expose the exact always-present quality contexts and orchestrate the flake-owned apps after a cache-warming Build Gate.

**Independent Test**: Structural assertions added to the workflow-lint surface fail against the old workflow, then pass after `.github/workflows/ci.yml` exposes all nine names, prescribed runners, Build Gate dependencies, and focused commands; the full gate remains green.

**Owned files**: `nix/checks.nix`, `.github/workflows/ci.yml`.

**Forbidden scope**: All application/test/UI sources; Cabal metadata; other workflows; specs, `gate.sh`, PR metadata, and ruleset state.

- [ ] T007 [US2] Add structural CI contract assertions to the `workflow-lint` surface in `nix/checks.nix` and record RED against the old `.github/workflows/ci.yml` before changing it.
- [ ] T008 [US2] Replace `.github/workflows/ci.yml` with unconditional `Build Gate`, Haskell, formatting, HLint, Cabal package, PureScript UI, workflow lint, dev-shell, and Darwin jobs using the exact contract names.
- [ ] T009 [US2] Make Linux jobs in `.github/workflows/ci.yml` run on `nixos`, depend on `build-gate`, and orchestrate focused flake apps while preserving the separate real `nix develop` build and macOS Darwin exception.
- [ ] T010 [US2] Record GREEN structural workflow proof, actionlint/shellcheck exit `0`, full `./gate.sh` exit `0`, and navigator verification in ignored `WIP.md` and paired runtime status before commit.

**Commit**: `ci: align GitHub Actions with flake checks`

**Trailer**: `Tasks: T007, T008, T009, T010`

---

## Slice 3: Ticket-Orchestrator Finalization

**Goal**: Independently prove local and hosted results, bind the observed contexts into the main ruleset, and complete ticket metadata before the standard gate-drop lifecycle.

**Independent Test**: Fresh local gate exits `0`; pull request #81 reports all nine jobs successful; ruleset `13867328` reports exactly those contexts and unchanged bypass actor `5`.

**Owner**: Ticket orchestrator; do not dispatch these metadata/external-state tasks to an implementation pair.

- [ ] T011 [US2] Rerun `./gate.sh`, inspect pull request #81 check conclusions, and record exact local/hosted evidence in the pull request body and `specs/077-authoritative-nix-ci/tasks.md`.
- [ ] T012 [US3] Replace ruleset `13867328` required contexts with the nine observed PR job names while preserving bypass actor `5`, then verify the returned ruleset JSON.
- [ ] T013 [US3] Update pull request #81 body to link parent epic #80, enumerate delivered local/GitHub surfaces, and complete final task accounting in `specs/077-authoritative-nix-ci/tasks.md`.

**Commit**: `chore: finalize issue 77 quality contract`

**Trailer**: `Tasks: T011, T012, T013`

After all tasks are checked, run the finalization audit, drop `gate.sh` in the lifecycle sentinel commit, push, wait for all checks to return green at the drop commit, and only then mark pull request #81 ready. Do not merge.

## Dependencies & Execution Order

1. Slice 1 is the serial foundation; it makes the local gate executable.
2. Slice 2 depends on Slice 1's flake app names and workflow-lint surface.
3. Slice 3 depends on Slice 2 being pushed and GitHub reporting the final job names.
4. Ruleset mutation follows observed green jobs, never speculative names.
5. Gate drop and mark-ready follow completed task accounting and the finalization audit.

## Parallel Opportunities

- T004 touches disjoint workflow-lint configuration files but remains under the same paired Slice 1 review/commit.
- Slices are intentionally serial because they share the quality contract and branch history.
- External GitHub check observation can overlap only with non-mutating PR-body preparation; the ruleset update waits for final names.

## Implementation Strategy

1. Establish executable local proof before changing hosted orchestration.
2. Use focused RED → GREEN evidence for both the check engine and workflow contract.
3. Freeze and push each navigator-verified slice only after the ticket owner independently reviews the diff and reruns `./gate.sh`.
4. Treat the ruleset as a final external projection of already-observed CI state.
