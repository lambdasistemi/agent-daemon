# Implementation Plan: Touch terminal command deck

**Branch:** `feat/92-touch-command-deck`  
**Draft PR:** [#93](https://github.com/lambdasistemi/tmux-ws/pull/93)

## Technical context

- The frontend is PureScript/Halogen with xterm.js wired through
  `ui/src/AgentDaemon/FFI/Terminal.{purs,js}` and rendered by `Main.purs`.
- `ui/dist/index.css` already owns responsive, safe-area, touch-target, and
  dark/light state rules. No new runtime package is needed.
- The xterm controller already sends terminal bytes over its existing socket.
  The new encoder uses only terminal data and xterm's public modes API; it does
  not create browser keyboard events.
- `nix/checks.nix` owns the authoritative UI check. The new dependency-free
  Node test runs there with the pinned Nix Node runtime.

## Design

`TerminalInput.mjs` is a browser-independent model with a small state value
(`ctrl`, `alt`, `shift`, `tmux`) and logical keys. It returns terminal data,
the next latch state, and repeat lifecycle decisions. `bootstrap.js` exposes
that module to the existing FFI global boundary, keeping FFI files free of
module imports. Node tests import the same module directly.

`Terminal.js` owns xterm-bound concerns: reading application-cursor mode,
writing model output to the existing socket, intercepting native keys only
while latches are armed, focus-preserving pointer handling, and bounded arrow
repeat cleanup. PureScript owns rendered latch state and accessible controls;
the FFI callback clears visual state when a native key consumes latches.
The existing Node model test also owns a pure native-key adapter proof: an
armed native key is consumed once, and the next unarmed key remains plain.

## Slices

### Slice 1 — Pure input model and authoritative tests

Create the dependency-free logical-key/latch/encoding model and Node tests.
Register the module in the bootstrap global boundary and run its test file from
the existing Nix UI check. This foundation is independently testable and adds
no user-visible behavior yet.

### Slice 2 — xterm integration and responsive command deck

Extend the typed FFI, controller, Halogen state/actions/rendering, and CSS to
  expose the eleven controls. Integrate the model for accessory and armed-native
input, public xterm cursor modes, focus preservation, and bounded arrow
repetition. The completed slice is usable end-to-end without a hardware key.

### Slice 3 — Operator documentation and live evidence

Document the deck in the supported operator guides. Run a live daemon/session
browser smoke at 390×844, 768×1024, and 1024×768, asserting controls, target
sizes, overflow, latch semantics, cursor modes, repeat cleanup, and no
console/runtime errors. Publish the hosted preview URL and link all evidence
from the PR.

## Owned files

- Slice 1: `ui/src/AgentDaemon/TerminalInput.mjs`,
  `ui/test/TerminalInput.test.mjs`, `ui/src/bootstrap.js`, `nix/checks.nix`.
- Slice 2: `ui/src/AgentDaemon/TerminalInput.mjs`,
  `ui/src/AgentDaemon/FFI/Terminal.purs`,
  `ui/src/AgentDaemon/FFI/Terminal.js`, `ui/src/Main.purs`,
  `ui/test/TerminalInput.test.mjs`, `ui/dist/index.css`, and
  `ui/dist/index.html` only for an asset cache token.
- Slice 3: `README.md`, `docs/index.md`, and external evidence files only.
- Orchestrator: `specs/092-touch-command-deck/*`, `gate.sh`, PR metadata, and
  runtime protocol files.

No slice may modify API/WebSocket/backend behavior, dependency pins, release
or packaging work, broad #79 documentation/governance, the GHC version, or
the canonical main checkout.

## Verification

- Slice 1: `nix run --quiet .#ui`, the focused Node test, then `./gate.sh`.
- Slice 2: focused model tests, UI build/lint/bundle, `./gate.sh`, and a live
  xterm smoke proving required byte sequences without synthetic key events.
- Slice 3: fresh full gate, three browser viewports, hosted preview, PR-body
  evidence, task/commit audit, and exact hosted checks. The PR stays draft;
  finalization does not merge it.
