# Implementation Plan: Touch-first tmux workspace

**Branch**: `feat/make-tmux-ws-touch-first-on-tablets-and-small-scre`  
**Issue**: [#75](https://github.com/lambdasistemi/tmux-ws/issues/75)

## Technical context

- PureScript/Halogen owns the rendered shell and existing actions.
- Plain CSS in `ui/dist/index.css` owns all visual and responsive behavior.
- Existing Lucide icons and xterm.js remain unchanged; no dependency work is
  needed.
- There is no frontend test harness. Proof is the PureScript/build gate plus a
  live daemon browser smoke at the three target viewports.

## Interaction design

The terminal remains the dominant center surface. The shell is divided into:

1. A compact identity/context header containing the product name, a connection
   status badge, and two resilient selectors for session and window.
2. The terminal workspace, which consumes all remaining space.
3. A stable action dock containing refresh, terminal controls, paste snippets,
   and settings. On touch layouts these actions use icon-plus-label affordances
   and safe-area padding so their purpose is not hidden behind tooltips.

Repository/documentation links move into a secondary utility area that remains
reachable but does not displace operational controls. Existing menus keep one
open surface at a time; small-screen CSS presents them as viewport-bound sheets.

## Responsive invariants

- No horizontal scrolling at any supported width.
- Session/window selectors share available width with `minmax(0, 1fr)` and
  ellipsis for long names.
- Coarse-pointer or narrow-screen actions are at least 44x44 CSS pixels.
- Dock and sheets use safe-area insets; the terminal is laid out around them,
  not underneath them.
- Desktop retains compact sizing and hover feedback, while focus-visible and
  active states work everywhere.

## Slice 1 — Deliver the touch-first shell

This is one bisect-safe vertical slice because the Halogen hierarchy and its CSS
layout must land together to remain usable.

Owned implementation files:

- `ui/src/Main.purs`
- `ui/dist/index.css`
- `ui/dist/index.html` only if a cache-busting query must change

The slice will reorganize existing render helpers into the identity/context
header, terminal workspace, stable action dock, and secondary utilities. It
will retain all action constructors and handlers, then add responsive,
coarse-pointer, safe-area, focus, and sheet styling. No generated bundle is
committed.

## Proof

1. Run `./gate.sh`.
2. Serve the branch build from an isolated local daemon/static directory.
3. At 390x844, 768x1024, and 1024x768, verify no horizontal overflow, inspect
   all required touch targets, open every menu/sheet, and capture screenshots.
4. At 768x1024, repeat the visual check in light theme.

