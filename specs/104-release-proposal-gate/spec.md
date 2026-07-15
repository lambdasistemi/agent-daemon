# Feature Specification: Version-independent release-plan validation

**Issue**: [#104](https://github.com/lambdasistemi/tmux-ws/issues/104)
**Parent**: [#80](https://github.com/lambdasistemi/tmux-ws/issues/80)
**Priority**: P1

## User story

As a maintainer, I can merge a generated Cabal-owned release proposal only
after the same authoritative gate that protects an ordinary pull request has
validated its exact head, including when that proposal increments the version
in `tmux-ws.cabal`.

## Problem

The release-plan check asserts that the live Cabal version is exactly `0.3.1`.
That assertion passes on current `main` but rejects the valid v0.4.0 proposal at
`4b9cc627a9d503a81aa6ea394a393b2a791ce529`. Its hosted Build Gate fails with:

```text
release-plan test: expected Cabal version 0.3.1, got 0.4.0
```

The test also uses `0.3.1` and `0.4.0` as deliberate fixture versions. Those
fixture values describe the scenario under test and must remain explicit,
stable, and independent of the version checked out at the repository root.

## Functional requirements

- **FR-001**: The release-plan test MUST derive the expected live version from
  `tmux-ws.cabal`; it MUST NOT require a particular current release number.
- **FR-002**: The Cabal file MUST remain the sole live version source of truth.
- **FR-003**: The synthetic repository MUST declare readable baseline and
  release fixture versions and normalize its copied Cabal file to that baseline
  before creating its baseline tag.
- **FR-004**: All fixture tag, proposal, publication, and idempotency assertions
  MUST use the declared fixture versions rather than scattered literals.
- **FR-005**: The unchanged test from PR #102 MUST be observed failing on the
  exact proposal head for the expected fixed-version reason before GREEN work.
- **FR-006**: The corrected test MUST pass both on this branch's current Cabal
  version and when overlaid onto an otherwise equivalent PR #102 proposal tree.
- **FR-007**: The behavior-changing diff MUST be confined to
  `test/release-plan.sh`.

## Success criteria

- **SC-001**: Exact PR #102 head `4b9cc627a9d503a81aa6ea394a393b2a791ce529`
  supplies recorded RED evidence with the expected `0.3.1` versus `0.4.0`
  failure.
- **SC-002**: `bash test/release-plan.sh` and `nix run --quiet .#release-plan`
  pass on the issue branch.
- **SC-003**: The corrected `test/release-plan.sh`, overlaid onto a detached
  copy of PR #102, passes without changing its Cabal version or release notes.
- **SC-004**: `nix run --quiet .#workflow-lint` and `./gate.sh` pass.
- **SC-005**: The final PR head is clean, contains no `gate.sh`, and all hosted
  checks required by the owner brief succeed on that exact SHA.

## Non-goals

- Changing application, API, UI, package, artifact, release workflow, release
  script, Cabal version, changelog, documentation, or Homebrew behavior.
- Mutating PR #102, `release/cabal-release`, ticket/PR #79, tags, releases, or
  previously published assets.
- Redesigning the Cabal-owned release planner or immutable tag publication.

## Evidence anchors

- Main baseline: `a3edae6a3805c4f998195ecc3f3c2d47cc356f90`.
- Proposal head: `4b9cc627a9d503a81aa6ea394a393b2a791ce529`.
- Failed hosted run/job: `29414859720` / `87350346383`.
