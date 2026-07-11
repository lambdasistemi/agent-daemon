# Tasks: Close the Current Pane or Window

Every behavior slice is one bisect-safe commit. The driver observes RED, the navigator approves RED before GREEN, and the navigator verifies GREEN before commit. Commit bodies carry the exact listed `Tasks:` IDs.

## Slice 1 — Pure model and preservation properties

- [X] T001 Define the valid close-current topology, scopes, snapshots, consequences, and pure prepare/execute transitions for invariants I1–I7.
- [X] T002 Add generated QuickCheck properties proving current-only effect, stale identity, survivor validity, exact cardinality, truthful termination, and single-use rejection.
- [X] T003 Register the module/spec and pass focused Haskell tests plus `./gate.sh`.

Commit: `feat: model close-current transitions`  
Trailer: `Tasks: T001, T002, T003`

## Slice 2 — Tmux live-boundary primitives

- [x] T004 Add internal current-context snapshot queries and conditional current-pane/current-window close primitives that fail closed on mismatch.
- [x] T005 Prove both actions, survivor selection, last-pane/window/session behavior, and deliberate races with disposable tmux sessions.
- [x] T006 Pass focused live Haskell tests and `./gate.sh` without exposing a client target surface.

Commit: `feat: close current tmux contexts safely`  
Trailer: `Tasks: T004, T005, T006`

## Slice 3 — Current-only Servant API

- [x] T007 Add opaque single-use confirmation types and STM state, consequence preview, execute results, and HTTP 409 stale errors.
- [x] T008 Add the four preview/execute routes and handlers with no pane/window target input.
- [x] T009 Add API integration tests for consequence classification, success, termination, invalid/reused tokens, and raced-current fail-closed refresh truth.
- [x] T010 Pass focused API/live Haskell tests and `./gate.sh`.

Commit: `feat: expose close-current API actions`  
Trailer: `Tasks: T007, T008, T009, T010`

## Slice 4 — Touch confirmations and recovery

- [x] T011 Add PureScript/JS API bindings and response types for pane/window preview and execution.
- [x] T012 Add exactly two attached-session actions with consequence-based, no-typing Cancel/destructive confirmation sheets and accessible labels.
- [x] T013 Reconnect/refresh a surviving context, show truthful session-ended state, and fail closed with actionable stale status and refresh.
- [x] T014 Add only the CSS needed for ≥44×44 touch controls, bounded sheets, destructive hierarchy, and all accepted viewports.
- [x] T015 Pass UI compile/lint/bundle proof and `./gate.sh`; document the no-unit-harness RED exception.

Commit: `feat: add touch close-current actions`  
Trailer: `Tasks: T011, T012, T013, T014, T015`

## Final verification and handoff — orchestrator owned

- [x] T016 Independently run focused Haskell/API/state-machine and disposable live-tmux proof, then fresh full local CI.
- [x] T017 Run touch browser smoke and capture reviewed evidence at 390×844, 768×1024, and 1024×768 with zero console/runtime errors.
- [x] T018 Audit the operator-approved Lean waiver, accepted semantics, task/commit accounting, PR assignment/label/links/body, and exact hosted checks.
- [x] T019 Pass finalization audit, remove `gate.sh` only in the final sentinel commit, push, and hand the draft PR back without merging.

## Proof-mechanism waiver

The operator explicitly waived adding Lean for #82 in `A-001-lean-scope.md`. This task ledger intentionally substitutes precise prose, pure Haskell/QuickCheck, Servant/API integration, disposable tmux boundary tests, and three-viewport browser proof. This changes only the proof mechanism; every product, TDD, pair-review, gate, and evidence requirement remains binding.
