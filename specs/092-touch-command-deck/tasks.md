# Tasks: Touch terminal command deck

Every behavior-changing slice is a single bisect-safe commit. Drivers perform
RED → navigator review → GREEN; each accepted commit retains its exact
`Tasks:` trailer and receives these checked boxes by amend before push.

## Bootstrap — already complete

- [X] T000 Create the isolated worktree, validate the baseline, add `gate.sh`,
  and open draft PR #93.

## Slice 1 — Pure input model and authoritative tests

- [X] T9201 Define the dependency-free logical key, latch, sequence, cursor
  mode, and bounded-repeat model.
- [X] T9202 Add Node tests for Ctrl-C, Shift-Tab, Alt text, Tmux-plus-arrow,
  cancellation/one-shot consumption, both cursor modes, and repeat stop paths.
- [X] T9203 Expose the model through `bootstrap.js` and run the focused test in
  the authoritative Nix UI check without adding a dependency or pin.
- [X] T9204 Run focused tests, `nix run --quiet .#ui`, and `./gate.sh`.

Commit: `feat: model terminal command deck input`
Trailer: `Tasks: T9201, T9202, T9203, T9204`

## Slice 2 — xterm integration and responsive command deck

- [X] T9205 Extend the pure model and typed xterm FFI for logical command-deck
  input, armed native-key handling, public cursor-mode selection, and repeat
  cleanup; add a RED/GREEN Node proof that native input consumes an armed latch
  once and leaves the following unarmed key plain.
- [X] T9206 Render accessible, cancellable Ctrl/Alt/Shift/Tmux latches and
  Esc/Tab/arrows/Enter controls that consume latches exactly once.
- [X] T9207 Preserve terminal/native-keyboard focus while operating controls;
  implement bounded pointer-hold arrow repetition without synthetic events.
- [X] T9208 Add safe-area-aware responsive CSS with 44×44 targets and visible
  dark/light, pressed, and focus states at every accepted viewport.
- [X] T9209 Run focused model/UI checks and `./gate.sh`; record live sequence
  smoke evidence in WIP.

Commit: `feat: add touch terminal command deck`
Trailer: `Tasks: T9205, T9206, T9207, T9208, T9209`

## Slice 3 — Operator documentation and evidence

- [X] T9210 Document command-deck controls, modifier cancellation/consumption,
  Tmux prefix, native-keyboard composition, cursor mode, and touch-only TUI use.
- [X] T9211 Capture browser evidence at 390×844, 768×1024, and 1024×768 for
  reachability, overflow, target size, latch semantics, repeat cleanup, and
  console/runtime-error absence.
- [X] T9212 Link the live PR preview and durable evidence from the draft PR,
  then re-run the full local gate.

Commit: `docs: document touch terminal command deck`
Trailer: `Tasks: T9210, T9211, T9212`

## Final verification and handoff — orchestrator owned

- [X] T9213 Independently review every accepted diff and commit/task linkage,
  run the fresh full gate, audit PR labels/assignee/links/body, and collect
  exact hosted check results without merging.
