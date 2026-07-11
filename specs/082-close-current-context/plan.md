# Implementation Plan: Close the Current Pane or Window

## Technical context

- Backend: Haskell 2021, Servant, STM, `process`, Hspec, QuickCheck.
- Boundary: real tmux server commands in disposable sessions.
- Frontend: PureScript, Halogen, JavaScript fetch FFI, plain CSS.
- Gate: Nix flake checks plus the real dev-shell build through `nix develop --quiet -c just ci`; focused UI proof through `nix run --quiet .#ui`.
- Branch: `feat/close-current-pane-or-window`; draft PR #83.

## Design decision

The API is current-context-only and two-phase:

- `POST /sessions/:sid/current-pane/close/preview`
- `POST /sessions/:sid/current-pane/close` with `{ "confirmation": "<opaque>" }`
- `POST /sessions/:sid/current-window/close/preview`
- `POST /sessions/:sid/current-window/close` with `{ "confirmation": "<opaque>" }`

Preview responses describe consequences and carry a server-minted opaque, single-use token. `SessionManager` stores only the newest pending confirmation per `(session, scope)` with its internal current-context snapshot. The execute handler consumes the token, resolves tmux currentness again, rejects mismatch with HTTP 409, and invokes a tmux-side conditional close that cannot fall through onto a different context. No client payload contains or selects a pane/window target.

Success returns whether the session ended and a consequence/status value. The UI reconnects the session terminal and refreshes windows when a context survives; otherwise it refreshes sessions and shows a truthful ended/disconnected state. Failure closes the confirmation sheet, reports the actionable error, and refreshes current truth without attempting another close.

## Discussion → proof → docs reconciliation

The accepted state machine and invariants I1–I7 are recorded in `spec.md`. The operator waived Lean because adding the repository's first formal toolchain would expand scope. The proof replacement is deliberately layered:

1. Pure Haskell topology transitions mirror the documented state machine.
2. QuickCheck properties quantify preservation, exact removal, termination, stale identity, and replay rejection over valid generated states.
3. Hspec/Servant integration proves route shape, token lifecycle, status mapping, and session registry behavior.
4. Disposable tmux sessions prove actual current-pane/current-window resolution, conditional race rejection, survivor selection, and last-context termination.
5. Browser smoke proves touch interaction and recovery at the three accepted viewports.

Any discovery that invalidates I1–I7 requires updating `spec.md`, this plan, `tasks.md`, the pure model, and mapped properties before continuing.

## Slices

### Slice 1 — Pure close-current model and properties

Add `AgentDaemon.Close` with the valid topology, close scopes, snapshots, consequences, preparation/validation, pure transitions, and invariant predicates. Add generated QuickCheck properties for I1–I7. Register the module/tests in Cabal. This is independently usable as the backend's decision core.

### Slice 2 — Atomic tmux close primitives and live boundary

Add current-context snapshot queries and conditional close-current-pane/window primitives to `AgentDaemon.Tmux`. Tests create disposable multi-window/multi-pane sessions and demonstrate the successful, last-context, and deliberately raced paths against a real tmux server. The primitive receives an internal expected snapshot, never a client target, and refuses to close if currentness changed.

### Slice 3 — Servant preview/execute API

Add JSON types, STM pending-confirmation state, the four current-only routes, handlers, conflict errors, single-use behavior, and API integration tests. Route/request inspection proves there is no arbitrary target field. The handler uses the pure model and Slice 2 boundary functions.

### Slice 4 — Touch UI, confirmations, and recovery

Add PureScript/JS bindings and Halogen confirmation state/actions. Put both actions in the attached-session settings surface, show consequence-based no-typing sheets, and handle survive/end/stale outcomes. Extend CSS only for touch-safe destructive grouping and sheets. With no PureScript unit harness in this repository, RED is the pre-change missing control/API behavior; proof is compiler/lint/bundle plus live browser assertions and screenshots.

## Owned files by slice

- Slice 1: `src/AgentDaemon/Close.hs`, `test/AgentDaemon/CloseSpec.hs`, `test/Main.hs` only if discovery requires it, `agent-daemon.cabal`.
- Slice 2: `src/AgentDaemon/Tmux.hs`, `test/AgentDaemon/TmuxCloseSpec.hs`, `agent-daemon.cabal`.
- Slice 3: `src/AgentDaemon/Types.hs`, `src/AgentDaemon/Api/Types.hs`, `src/AgentDaemon/Api.hs`, `test/AgentDaemon/ApiSpec.hs`, plus a minimal `src/AgentDaemon/Tmux.hs` forward edit exposing only the already-computed consequence of an otherwise opaque prepared close.
- Slice 4: `ui/src/AgentDaemon/Types.purs`, `ui/src/AgentDaemon/Api.purs`, `ui/src/AgentDaemon/Api.js`, `ui/src/Main.purs`, `ui/dist/index.css`.
- Orchestrator: `specs/082-close-current-context/*`, `gate.sh`, PR metadata, runtime evidence outside the repository.

No slice may touch #78 release/packaging/workflow scope, #79 broad docs/governance scope, unrelated terminal/session/paste behavior, the GHC version, or the main worktree's untracked specifications.

## Verification strategy

- Slice focused Haskell proof: `nix run --quiet .#haskell-tests` and `./gate.sh`.
- Slice focused UI proof: `nix run --quiet .#ui`, `nix develop --quiet -c bash -lc 'cd ui && just ci'` when available, then `./gate.sh`.
- Live boundary: named disposable tmux specs for pane, last-pane/window, window, last-window/session, and raced currentness.
- Browser: isolated live daemon/session, touch/CDP interaction at 390×844, 768×1024, and 1024×768; assert no overflow, every destructive control ≥44×44 CSS px, sheets in bounds, Cancel non-destructive, survive reconnect, end disconnect, stale refresh, console errors 0, runtime exceptions 0; save screenshots/transcript outside the repo and link evidence in PR #83.
- Final local: fresh `./gate.sh`, fresh `nix develop --quiet -c just ci`, focused tests/UI, diff/status/task/message audit.
- Hosted: exact required PR checks by name and conclusion.

## Formalization waiver

Per parent answer `A-001-lean-scope.md`, #82 intentionally adds no Lean files or toolchain. The state-machine/QuickCheck/live-boundary stack above is the operator-approved replacement and must be recorded in the final PR description.
