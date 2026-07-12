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

### Correction slice — visible deck layout regression

The accepted screenshot evidence found a hierarchy bug: the deck is nested in
`.terminal-wrap`, whose `overflow: hidden` clips the controls while the
workspace grid can allocate rows only to direct children. First add a failing
browser-layout regression. It must serve the built UI with an attached-session
fixture, then at 390×844, 768×1024, and 1024×768 assert all eleven
`[data-command-deck-control]` elements have 44×44-or-larger boxes that
intersect the viewport and win a centre-point `elementFromPoint` hit test.
That proves neither terminal clipping nor a fixed workspace dock covers them.

Run the regression in the authoritative Linux UI check with Nix-provided
Playwright and its browsers—no npm dependency, package-lock, or pin change.
Then make the smallest render hierarchy/CSS correction: the terminal remains
in the flexible workspace row and the deck becomes a direct workspace child in
the allocated auto row. Preserve safe-area padding, target sizes, source
order, xterm sizing, and all input semantics. The navigator must independently
reproduce the test, inspect hit targets, and capture fresh screenshots at all
three viewports before acceptance.

## Owned files

- Slice 1: `ui/src/AgentDaemon/TerminalInput.mjs`,
  `ui/test/TerminalInput.test.mjs`, `ui/src/bootstrap.js`, `nix/checks.nix`.
- Slice 2: `ui/src/AgentDaemon/TerminalInput.mjs`,
  `ui/src/AgentDaemon/FFI/Terminal.purs`,
  `ui/src/AgentDaemon/FFI/Terminal.js`, `ui/src/Main.purs`,
  `ui/test/TerminalInput.test.mjs`, `ui/dist/index.css`, and
  `ui/dist/index.html` only for an asset cache token.
- Slice 3: `README.md`, `docs/index.md`, and external evidence files only.
- Correction slice: `ui/src/Main.purs`, `ui/dist/index.css`,
  `ui/test/CommandDeckLayout.test.mjs`, and `nix/checks.nix` only.
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
- Correction slice: first observe the Playwright layout regression fail on the
  clipped hierarchy; after the minimal repair, run it at all three viewports,
  the focused UI checks, and `./gate.sh`. Refresh the real tailnet preview and
  its screenshots at the corrected exact head before final hosted CI. For the
  hardened self-hosted runner only, reproduce the Chromium zygote SIGTRAP
  under its exact system-call filter, then add only `--no-zygote` to the
  Playwright launch with a concise rationale. Do not weaken runner hardening
  or alter application behavior.
