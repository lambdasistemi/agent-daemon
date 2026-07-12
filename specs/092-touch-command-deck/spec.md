# Feature Specification: Touch terminal command deck

**Issue:** [#92](https://github.com/lambdasistemi/tmux-ws/issues/92)  
**Parent:** [#80](https://github.com/lambdasistemi/tmux-ws/issues/80)  
**Priority:** P1

## P1 user story

As a touch-only tablet operator, I can send the tmux prefixes, modifiers, and
terminal navigation keys that an interactive terminal application expects,
without replacing the native alphanumeric keyboard.

## Input contract

The command deck presents **Esc**, **Tab**, **Ctrl**, **Alt**, **Shift**,
**Tmux**, **Left**, **Up**, **Down**, **Right**, and **Enter** whenever a
terminal is attached. Ctrl, Alt, Shift, and Tmux are visible one-shot latches:

- Tapping an inactive latch arms it; tapping that same latch cancels it.
- A key dispatch consumes every armed latch exactly once and clears its
  `aria-pressed` state. Cancelling a latch sends no terminal data.
- **Tmux** contributes the literal Ctrl-B prefix (`\x02`) before the next
  accessory or native-keyboard key; it is not a configurable shortcut.
- Native keyboard input is left to xterm unchanged when no latch is armed. If
  one or more latches are armed, the next native key is encoded once by the
  command-deck model and xterm's default handling for that key is suppressed.

The encoder emits Esc, Tab, Enter, C0 control combinations, Alt-prefixed
input, and normal or modified cursor sequences. A plain arrow is `CSI A/B/C/D`
in normal cursor mode and `SS3 A/B/C/D` while xterm's public
`terminal.modes.applicationCursorKeysMode` is true. Modified cursor keys use
the standard CSI modifier form. A Tmux-plus-arrow dispatch therefore begins
with Ctrl-B and then uses the current cursor mode's arrow sequence.

Only arrow buttons support press-and-hold. A primary pointer-down sends one
arrow immediately, then begins deliberate bounded repetition after a short
delay. Pointer-up, pointer-cancel, pointer-leave, window blur, terminal
detach, and the configured repeat bound all stop the lifecycle; ordinary taps
never schedule a repeat.

## Functional requirements

- **FR-001:** An attached terminal exposes every required control in a compact,
  always-reachable deck; detached terminals expose no actionable deck.
- **FR-002:** Ctrl, Alt, Shift, and Tmux are individually cancellable, have
  truthful `aria-pressed` values, and are consumed once by accessory and native
  input alike.
- **FR-003:** The deck proves Ctrl-C, Shift-Tab, Alt-prefixed text, and
  Tmux-plus-arrow encodings.
- **FR-004:** Arrow encoding reads xterm's public cursor-mode state at dispatch
  time and its repeat lifecycle cannot leak a timer after release or cancel.
- **FR-005:** Deck pointer/touch handling preserves an existing terminal/native
  keyboard focus relationship; it does not synthesize browser `KeyboardEvent`s
  or dismiss the tablet keyboard merely by operating a control.
- **FR-006:** Every deck target is at least 44 by 44 CSS pixels on touch
  layouts, has dark/light active and focus states, honours safe areas, and is
  never horizontally clipped at 390×844, 768×1024, or 1024×768.
- **FR-007:** A pure input model has automated tests for encoding, latch
  consumption/cancellation, cursor modes, and repeat lifecycle. The
  authoritative Nix UI check executes those tests.
- **FR-008:** Operator documentation explains the deck, one-shot modifiers,
  Tmux prefix, native-keyboard composition, and touch-only TUI workflow.
- **FR-009:** The draft PR supplies a live preview URL and browser evidence at
  all three accepted viewports.

## Success criteria

- Touching each control sends the documented bytes once; untouched native text
  entry remains plain xterm input.
- Browser assertions report no horizontal overflow, every deck target is at
  least 44×44 CSS pixels, and the deck remains reachable at every viewport.
- The focused model tests, `nix flake check --no-eval-cache`,
  `nix develop --quiet -c just ci`, and `./gate.sh` pass.

## Non-goals

- A full virtual alphanumeric/function/symbol keyboard or third-party keyboard
  dependency.
- Configurable layouts or a remappable tmux prefix.
- Browser `KeyboardEvent` synthesis, backend/API/WebSocket changes, packaging,
  release automation, or a GHC upgrade.
