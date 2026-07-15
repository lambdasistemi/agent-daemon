# Implementation Plan: Version-independent release-plan validation

## Scope and constraints

This is one behavior-changing, bisect-safe test slice. The only owned code file
is `test/release-plan.sh`; the ticket owner separately owns this specification,
`gate.sh`, task accounting, PR metadata, and verification evidence.

The change preserves the Cabal file as the live version source and makes the
test's synthetic repository independent of that live value. No release script,
workflow, package output, artifact name, version, changelog, documentation, or
publication state may change.

## Design

1. Derive an independent expected live version from the single `version:` field
   in root `tmux-ws.cabal`, then compare `get-cabal-version` with that derived
   value. The assertion continues testing the helper without encoding the
   current release number.
2. Declare a fixed fixture baseline (`0.3.1`) and fixture release (`0.4.0`) near
   the fixture setup. These are scenario inputs, not repository state.
3. Normalize each synthetic repository's copied Cabal file to the fixture
   baseline before its initial commit and annotated baseline tag. Use the named
   fixture values for tag creation, expected proposal output, publication
   transition, release assertions, and idempotency counting.
4. Keep all literals intentional and readable, including clear failure messages
   that distinguish the live version contract from the synthetic fixture.

## TDD and verification

### RED

Use a detached temporary worktree at exact PR #102 head
`4b9cc627a9d503a81aa6ea394a393b2a791ce529`. Run its unchanged focused
release-plan check and record the non-zero exit plus the expected fixed-version
failure. Do not change or push its branch.

### GREEN

- Run `bash test/release-plan.sh` in the issue worktree.
- Run `nix run --quiet .#release-plan` in the issue worktree.
- Overlay only the corrected `test/release-plan.sh` onto the detached PR #102
  tree and run the focused Bash and Nix-backed checks there.
- Run `nix run --quiet .#workflow-lint`.
- Run `./gate.sh`, whose durable route includes
  `nix develop --quiet -c just ci`.

Record command, exit code, and salient output in `WIP.md` and the worker handoff
artifacts. Remove the detached worktree after evidence is preserved.

## Commit

Exactly one implementation commit:

```text
fix: make release-plan test version-independent

Derive the live expectation from the Cabal source of truth and isolate the
synthetic baseline/release fixture from the checkout version.

Tasks: T104, T105, T106, T107
```

The navigator must approve RED and GREEN before the driver commits. The ticket
owner then reviews the full diff, re-runs the gate, checks all task boxes in the
same amended commit, and pushes it.

## Hosted completion

After the ticket gate passes and `gate.sh` is removed, verify exact-final-head
Build Gate, every NixOS CI job, Linux artifact build/smoke, and Darwin jobs.
Do not merge or publish from this ticket.
