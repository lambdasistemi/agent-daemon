# Feature Specification: Touch-first tmux workspace

**Issue**: [#75](https://github.com/lambdasistemi/tmux-ws/issues/75)  
**Priority**: P1

## Paramount user story

As an operator using only a touchscreen, I can navigate sessions and windows,
control the terminal, and use paste snippets without needing a hardware
keyboard or mouse.

## User journeys

### US1 — Find the active workspace

On phone or tablet, the operator can immediately distinguish connection state,
active session, and active tmux window. Long names truncate without pushing any
control off-screen.

### US2 — Operate without hardware input

The operator can reach refresh, session/window switching and creation,
terminal keys (`Esc`, `Ctrl-b`, and command mode), copy/select, live mode, paste
snippets, and settings by touch. No core action depends on hover or a physical
keyboard.

### US3 — Work across device shapes

The same interface remains usable at phone portrait (390x844), tablet portrait
(768x1024), tablet landscape (1024x768), and desktop widths. Menus stay within
the visible viewport and terminal space remains the dominant surface.

## Functional requirements

- **FR-001**: Present brand and connection state separately from the active
  session/window context.
- **FR-002**: Keep session and window selectors visible and reachable without
  horizontal scrolling.
- **FR-003**: Provide a stable touch action surface for refresh, terminal
  controls, paste snippets, and settings.
- **FR-004**: Give every interactive control a minimum 44x44 CSS-pixel target
  on coarse-pointer/small-screen devices, with visible pressed, active, and
  focus states.
- **FR-005**: Render menus as viewport-safe popovers on wider screens and
  touch-friendly sheets on smaller screens.
- **FR-006**: Respect `env(safe-area-inset-*)` and never overlay core controls
  on the terminal viewport.
- **FR-007**: Preserve all existing actions, dark/light themes, terminal
  behavior, and desktop operation.
- **FR-008**: Keep repository and documentation links reachable without making
  them compete with primary touch controls.

## Success criteria

- At 390x844, 768x1024, and 1024x768, `scrollWidth` does not exceed
  `clientWidth` and every required control has a visible, tappable target.
- Coarse-pointer controls measure at least 44x44 CSS pixels.
- Opening session, window, terminal, paste, and settings surfaces keeps their
  bounding boxes inside the viewport.
- Visual smoke screenshots show legible hierarchy in dark theme at all target
  viewports and in light theme at one tablet viewport.
- `./gate.sh` exits 0 after the implementation.

## Non-goals

- Backend API or WebSocket protocol changes.
- New runtime dependencies.
- Replacing xterm.js or changing terminal emulation internals.
- Changing session lifecycle semantics or paste payload semantics.

