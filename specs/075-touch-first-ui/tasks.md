# Tasks: Touch-first tmux workspace

**Spec**: [spec.md](spec.md)  
**Plan**: [plan.md](plan.md)

## Slice 1 — Deliver the touch-first shell

- [ ] T7501 Reorganize `ui/src/Main.purs` into a clear identity/context header,
  terminal workspace, stable action dock, and reachable secondary utilities
  while preserving every existing action.
- [ ] T7502 Implement responsive phone/tablet/desktop layout, safe-area handling,
  viewport-bound sheets, and long-label containment in `ui/dist/index.css`.
- [ ] T7503 Ensure coarse-pointer interactive targets are at least 44x44 CSS
  pixels and add visible focus, pressed, active, and disabled states.
- [ ] T7504 Run `./gate.sh` and record the successful result.
- [ ] T7505 Smoke 390x844, 768x1024, and 1024x768 in a live branch build;
  verify overflow, target sizes, touch workflows, and menu bounds.
- [ ] T7506 Capture dark-theme screenshots at all three target viewports and a
  light-theme tablet screenshot for review.
