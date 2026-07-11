# Feature Specification: Close the Current Pane or Window

**Issue:** #82  
**Parent:** #80  
**Dependency:** #75, merged through PR #76 at `177679658ed21dc30cf59f5895195d2a73831ccb`  
**Priority:** P1  
**Command recovery:** yes — **Close this pane** and **Close this window**

## P1 user story

As a touch-only operator, I close the pane or window I am currently viewing and observe tmux-ws attach to the surviving context without naming or selecting a target.

## Accepted product semantics

There are exactly two actions:

1. **Close this pane** affects only the active pane in the window currently being viewed.
2. **Close this window** affects only the window currently being viewed and all panes inside it.

The operator never sees, chooses, or types a pane name, window name, index, tmux ID, or target. There is no pane list, arbitrary target picker, or close action for a non-current context. The server resolves currentness at execution time, and the client cannot turn either route into an arbitrary-target operation.

## State-machine model

A live session is a non-empty ordered collection of windows. Every live window is a non-empty ordered collection of panes. Exactly one window is current, and exactly one pane in that window is current.

A close interaction has two phases:

1. `prepare(scope, state)` asks the server for a consequence preview. The server resolves the current context and records a single-use opaque confirmation bound to the session, scope, current window, current pane where applicable, and topology counts.
2. `execute(token, freshState)` resolves currentness again. It proceeds only when the token is the latest unused confirmation for the same session/scope and the freshly resolved current context equals the recorded context. Otherwise it returns `stale-current-context` and makes no state change.

The pure transitions are:

- `closeCurrentPane` with more than one pane removes exactly the current pane; the same window survives and tmux chooses its next current pane.
- `closeCurrentPane` on the last pane with more than one window removes exactly that window; tmux chooses a surviving current window and pane.
- `closeCurrentPane` on the last pane of the last window ends the session.
- `closeCurrentWindow` with more than one window removes exactly the current window and every pane in it; tmux chooses a surviving current window and pane.
- `closeCurrentWindow` on the last window ends the session.
- A stale, unknown, reused, wrong-session, or wrong-scope token is the identity transition: nothing closes.

### Stable invariants

- **I1 — Current-only effect:** a successful transition removes only the context that was current both at preparation and execution.
- **I2 — No client-selected target:** execution input contains only a server-minted opaque token; no route accepts a pane/window identifier, name, or index as the close target.
- **I3 — Stale identity:** when the fresh current context differs from the prepared context, every window and pane remains present.
- **I4 — Survivor well-formedness:** a surviving session has at least one window; every surviving window has at least one pane; exactly one surviving window and pane are current.
- **I5 — Exact cardinality:** pane-close removes one pane, except that removing a last pane removes its now-empty window; window-close removes one window and all of its panes; no other cardinality changes.
- **I6 — Truthful termination:** the session ends exactly when the action removes the last window (directly, or by removing its last pane).
- **I7 — Single use:** a confirmation is consumed by its first execution attempt, successful or stale, and cannot be replayed.

Each invariant is implemented as a pure Haskell transition/predicate and mapped to QuickCheck preservation properties. Real disposable-tmux tests prove that the subprocess layer agrees with the model at the live boundary.

## Functional requirements

- **FR-001:** The touch UI exposes exactly **Close this pane** and **Close this window** for the attached session.
- **FR-002:** Opening either action requests a server-authored consequence preview and requires no typing.
- **FR-003:** Confirmation presents large **Cancel** and destructive action buttons and identifies consequences, never tmux identifiers.
- **FR-004:** Pane confirmation warns when the pane is the window's last pane and when that also ends the session.
- **FR-005:** Window confirmation warns when it is the session's last window.
- **FR-006:** Close API routes accept no client-selected target. The server resolves currentness immediately before the close.
- **FR-007:** Changed currentness, invalid/reused confirmation, or tmux failure fails closed with an actionable response and a truthful UI refresh.
- **FR-008:** After success the terminal reconnects to the surviving context selected by tmux. If none survives, the UI reports a session-ended/disconnected state.
- **FR-009:** Haskell properties cover invariants I1–I7.
- **FR-010:** API and disposable-tmux integration cover both actions, multi-context survival, last-pane/window termination, token replay, and raced-current rejection.
- **FR-011:** Browser smoke exercises reachability, both confirmation sheets, Cancel, success recovery, and failure refresh at 390×844, 768×1024, and 1024×768.

## Success criteria

- **SC-001:** Neither close request body nor route contains a pane/window target field.
- **SC-002:** All pure state-machine properties pass with generated valid topologies and actions.
- **SC-003:** A deliberately raced disposable-tmux request returns conflict and retains every pre-race context.
- **SC-004:** Successful disposable-tmux closes affect only the prepared current context and report the surviving/ended state truthfully.
- **SC-005:** At all three viewports, destructive controls are reachable by touch, confirmation controls are at least 44×44 CSS pixels, and no horizontal overflow or out-of-bounds sheet appears.
- **SC-006:** `nix develop --quiet -c just ci`, `nix run --quiet .#ui`, the ticket gate, and all authoritative hosted checks pass.

## Non-goals

- Closing a non-current pane or window.
- Pane/window target pickers or exposing identifiers.
- Renaming panes or windows.
- Redesigning whole-session stop semantics.
- Keyboard-only shortcuts as the primary interaction.
- Release, packaging, workflow, broad documentation, GHC upgrade, or production publication work.

## Formalization waiver

The repository has no Lean project or Lean toolchain. The operator explicitly chose option 2 in `A-001-lean-scope.md`: do not add Lean for #82. This is a deliberate proof-mechanism waiver, not an omitted design step. The rigorous replacement is precise state-machine prose, pure Haskell transitions, QuickCheck preservation properties, API integration, disposable live-tmux proof, and browser proof. All product semantics and other delivery requirements remain unchanged.
