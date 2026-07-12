const latchNames = new Set(["ctrl", "alt", "shift", "tmux"]);
const arrowFinals = {
  ArrowDown: "B",
  ArrowLeft: "D",
  ArrowRight: "C",
  ArrowUp: "A"
};

const emptyLatches = () => ({
  alt: false,
  ctrl: false,
  shift: false,
  tmux: false
});

export const createTerminalInput = emptyLatches;

export const toggleLatch = (latches, latch) => {
  if (!latchNames.has(latch)) {
    throw new Error(`Unknown terminal latch: ${latch}`);
  }

  return { ...latches, [latch]: !latches[latch] };
};

const cursorModifier = latches =>
  1 + (latches.shift ? 1 : 0) + (latches.alt ? 2 : 0) + (latches.ctrl ? 4 : 0);

const controlCharacter = key => {
  if (!/^[a-z]$/i.test(key)) {
    return key;
  }

  return String.fromCharCode(key.toUpperCase().charCodeAt(0) - 64);
};

const encodeArrow = (key, latches, applicationCursorKeysMode) => {
  const final = arrowFinals[key];
  const modifier = cursorModifier(latches);

  if (modifier !== 1) {
    return `\x1b[1;${modifier}${final}`;
  }

  return applicationCursorKeysMode ? `\x1bO${final}` : `\x1b[${final}`;
};

const encodeKey = (key, latches, applicationCursorKeysMode) => {
  if (key in arrowFinals) {
    return encodeArrow(key, latches, applicationCursorKeysMode);
  }

  if (key === "Esc") {
    return "\x1b";
  }

  if (key === "Tab") {
    return latches.shift ? "\x1b[Z" : "\t";
  }

  if (key === "Enter") {
    return "\r";
  }

  const text = latches.shift && key.length === 1 ? key.toUpperCase() : key;
  const encoded = latches.ctrl ? controlCharacter(text) : text;
  return latches.alt ? `\x1b${encoded}` : encoded;
};

export const dispatchKey = (
  latches,
  key,
  { applicationCursorKeysMode = false } = {}
) => ({
  data: `${latches.tmux ? "\x02" : ""}${encodeKey(
    key,
    latches,
    applicationCursorKeysMode
  )}`,
  latches: emptyLatches()
});

export const beginArrowRepeat = (
  key,
  { delayMs = 250, limit = 12 } = {}
) => {
  if (!(key in arrowFinals)) {
    return { decision: { type: "none" }, repeat: null };
  }

  return {
    decision: { type: "schedule", delayMs },
    repeat: { delayMs, key, remaining: limit }
  };
};

export const advanceArrowRepeat = state => {
  const repeat = state?.repeat ?? state;

  if (repeat == null || repeat.remaining <= 0) {
    return { decision: { type: "none" }, repeat: null };
  }

  const next = { ...repeat, remaining: repeat.remaining - 1 };
  if (next.remaining === 0) {
    return {
      decision: { type: "emit-and-stop", reason: "bound" },
      repeat: null
    };
  }

  return {
    decision: { type: "emit-and-schedule", delayMs: next.delayMs },
    repeat: next
  };
};

export const stopArrowRepeat = (_repeat, reason) => ({
  decision: { type: "stop", reason },
  repeat: null
});
