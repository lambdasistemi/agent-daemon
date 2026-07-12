import assert from "node:assert/strict";
import test from "node:test";

import {
  advanceArrowRepeat,
  beginArrowRepeat,
  consumeNativeKey,
  createTerminalInput,
  dispatchKey,
  suppressNativeKeyPhase,
  stopArrowRepeat,
  toggleLatch
} from "../src/AgentDaemon/TerminalInput.mjs";

test("encodes Ctrl-C and consumes Ctrl once", () => {
  const armed = toggleLatch(createTerminalInput(), "ctrl");
  const first = dispatchKey(armed, "c");

  assert.equal(first.data, "\x03");
  assert.deepEqual(first.latches, {
    alt: false,
    ctrl: false,
    shift: false,
    tmux: false
  });
  assert.equal(dispatchKey(first.latches, "c").data, "c");
});

test("consumes an armed native Ctrl-C once and leaves the following native c plain", () => {
  const armed = toggleLatch(createTerminalInput(), "ctrl");
  const first = consumeNativeKey(armed, "c");

  assert.deepEqual(first, {
    consumed: true,
    data: "\x03",
    latches: createTerminalInput()
  });
  assert.deepEqual(consumeNativeKey(first.latches, "c"), {
    consumed: false,
    data: "c",
    latches: createTerminalInput()
  });
});

test("suppresses only the remaining xterm phases of a consumed native key", () => {
  assert.deepEqual(suppressNativeKeyPhase("c", "c", "keypress"), {
    suppressed: true,
    suppressedKey: "c"
  });
  assert.deepEqual(suppressNativeKeyPhase("c", "c", "keyup"), {
    suppressed: true,
    suppressedKey: null
  });
  assert.deepEqual(suppressNativeKeyPhase(null, "c", "keydown"), {
    suppressed: false,
    suppressedKey: null
  });
});

test("encodes Shift-Tab", () => {
  const armed = toggleLatch(createTerminalInput(), "shift");

  assert.equal(dispatchKey(armed, "Tab").data, "\x1b[Z");
});

test("prefixes Alt text with Escape", () => {
  const armed = toggleLatch(createTerminalInput(), "alt");

  assert.equal(dispatchKey(armed, "x").data, "\x1bx");
});

test("prefixes a normal-mode arrow with literal Ctrl-B when Tmux is armed", () => {
  const armed = toggleLatch(createTerminalInput(), "tmux");

  assert.equal(dispatchKey(armed, "ArrowUp").data, "\x02\x1b[A");
});

test("uses SS3 arrows in application cursor mode", () => {
  assert.equal(
    dispatchKey(createTerminalInput(), "ArrowRight", {
      applicationCursorKeysMode: true
    }).data,
    "\x1bOC"
  );
});

test("cancelling a latch emits nothing and leaves the next key unmodified", () => {
  const armed = toggleLatch(createTerminalInput(), "alt");
  const cancelled = toggleLatch(armed, "alt");

  assert.deepEqual(cancelled, createTerminalInput());
  assert.equal(dispatchKey(cancelled, "x").data, "x");
});

test("consumes every armed latch exactly once", () => {
  const armed = ["ctrl", "alt", "shift", "tmux"].reduce(
    toggleLatch,
    createTerminalInput()
  );
  const first = dispatchKey(armed, "ArrowLeft");

  assert.equal(first.data, "\x02\x1b[1;8D");
  assert.deepEqual(first.latches, createTerminalInput());
  assert.equal(dispatchKey(first.latches, "ArrowLeft").data, "\x1b[D");
});

test("bounds arrow repeat and stops it on every cancellation path", () => {
  const initial = beginArrowRepeat("ArrowDown", { limit: 2, delayMs: 100 });

  assert.deepEqual(initial.decision, { type: "schedule", delayMs: 100 });

  const first = advanceArrowRepeat(initial);
  assert.deepEqual(first.decision, { type: "emit-and-schedule", delayMs: 100 });

  const bounded = advanceArrowRepeat(first.repeat);
  assert.deepEqual(bounded.decision, { type: "emit-and-stop", reason: "bound" });

  for (const reason of ["pointer-up", "pointer-cancel", "pointer-leave", "blur", "detach"]) {
    assert.deepEqual(stopArrowRepeat(initial, reason), {
      decision: { type: "stop", reason },
      repeat: null
    });
  }
});

test("does not schedule repeat lifecycle decisions for non-arrow keys", () => {
  assert.deepEqual(beginArrowRepeat("Enter"), {
    decision: { type: "none" },
    repeat: null
  });
});
