const terminalFontFamily = [
  '"AgentJetBrainsMono"',
  '"Symbols Nerd Font Mono"',
  '"AgentSymbols"',
  '"Noto Sans Mono"',
  '"Noto Sans Symbols 2"',
  '"Apple Color Emoji"',
  '"Segoe UI Emoji"',
  "ui-monospace",
  "SFMono-Regular",
  "Menlo",
  "Consolas",
  "monospace"
].join(", ");

const terminalTheme = (theme) => {
  if (theme === "light") {
    return {
      background: "#ffffff",
      foreground: "#1b2430",
      cursor: "#1f6d86",
      selectionBackground: "#cfe7ef",
      black: "#1b2430",
      red: "#a43e47",
      green: "#28724f",
      yellow: "#8a6300",
      blue: "#235d9b",
      magenta: "#7c4d91",
      cyan: "#1f6d86",
      white: "#eef1f5",
      brightBlack: "#667085",
      brightRed: "#c9515b",
      brightGreen: "#328761",
      brightYellow: "#a97900",
      brightBlue: "#2f72b8",
      brightMagenta: "#925eb0",
      brightCyan: "#27809b",
      brightWhite: "#ffffff"
    };
  }
  return {
    background: "#0f1115",
    foreground: "#e6e8ee",
    cursor: "#7fd1e8",
    selectionBackground: "#2d5362",
    black: "#0f1115",
    red: "#e06c75",
    green: "#98c379",
    yellow: "#e5c07b",
    blue: "#61afef",
    magenta: "#c678dd",
    cyan: "#56b6c2",
    white: "#e6e8ee",
    brightBlack: "#5c6675",
    brightRed: "#f07178",
    brightGreen: "#b5e890",
    brightYellow: "#ffd580",
    brightBlue: "#7cc7ff",
    brightMagenta: "#d79bf2",
    brightCyan: "#7fd1e8",
    brightWhite: "#ffffff"
  };
};

const textEncoder = new TextEncoder();

const sendResize = (controller, cols, rows) => {
  if (controller.socket && controller.socket.readyState === WebSocket.OPEN) {
    controller.socket.send(textEncoder.encode(`\x01${cols};${rows}`));
  }
};

const sendTerminalData = (controller, data) => {
  if (controller.socket && controller.socket.readyState === WebSocket.OPEN) {
    controller.socket.send(textEncoder.encode(data));
  }
};

const normalizePasteData = (value) =>
  String(value).replace(/\r\n/g, "\n").replace(/\n/g, "\r");

const hasMeasurableSize = (element) =>
  element &&
  element.isConnected &&
  element.getBoundingClientRect().width > 0 &&
  element.getBoundingClientRect().height > 0;

const fitNow = (controller) => {
  if (!hasMeasurableSize(controller.element)) return false;
  try {
    controller.fit.fit();
    sendResize(controller, controller.term.cols, controller.term.rows);
    return true;
  } catch (_) {
    return false;
  }
};

const scheduleFit = (controller) => {
  if (controller.fitPending) {
    controller.fitAgain = true;
    return;
  }

  controller.fitPending = true;
  controller.fitAgain = false;

  const delays = [0, 0, 32, 96, 192];
  let index = 0;

  const finish = () => {
    controller.fitPending = false;
    if (controller.fitAgain) scheduleFit(controller);
  };

  const step = () => {
    fitNow(controller);
    index += 1;
    if (index >= delays.length) {
      finish();
      return;
    }
    const delay = delays[index];
    if (delay === 0) {
      window.requestAnimationFrame(step);
    } else {
      window.setTimeout(() => window.requestAnimationFrame(step), delay);
    }
  };

  window.requestAnimationFrame(step);
};

const openTerminalLink = (callbacks) => (_event, uri) => {
  const target = window.open();
  if (target) {
    try {
      target.opener = null;
    } catch (_) {
      // Ignore browsers that expose opener as read-only.
    }
    target.location.href = uri;
    callbacks.onLinkOpened();
  } else {
    callbacks.onLinkBlocked();
  }
};

const terminalLineHeight = (controller) => {
  const rect = controller.element && controller.element.getBoundingClientRect();
  if (!rect || !controller.term.rows) return 16;
  return Math.max(8, rect.height / controller.term.rows);
};

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

const terminalScreenElement = (controller) =>
  (controller.element && controller.element.querySelector(".xterm-screen")) ||
  controller.element;

const touchToBufferCell = (controller, touch) => {
  const screen = terminalScreenElement(controller);
  const buffer = controller.term.buffer && controller.term.buffer.active;
  if (!screen || !buffer || !controller.term.cols || !controller.term.rows) return null;

  const rect = screen.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return null;

  const col = clamp(
    Math.floor(((touch.clientX - rect.left) / rect.width) * controller.term.cols),
    0,
    controller.term.cols - 1
  );
  const visibleRow = clamp(
    Math.floor(((touch.clientY - rect.top) / rect.height) * controller.term.rows),
    0,
    controller.term.rows - 1
  );

  return {
    col,
    row: (buffer.viewportY || 0) + visibleRow
  };
};

const selectionRange = (controller, start, end) => {
  let first = start;
  let last = end;
  if (last.row < first.row || (last.row === first.row && last.col < first.col)) {
    first = end;
    last = start;
  }

  return {
    col: first.col,
    row: first.row,
    length: Math.max(
      1,
      (last.row - first.row) * controller.term.cols + (last.col - first.col) + 1
    )
  };
};

const handleTouchSelectionStart = (controller, event) => {
  if (!controller.selectionMode) return false;

  event.preventDefault();
  event.stopImmediatePropagation();

  if (event.touches.length !== 1) return true;

  const anchor = touchToBufferCell(controller, event.touches[0]);
  if (!anchor) return true;

  blurTerminalInput(controller);
  if (typeof controller.term.clearSelection === "function") {
    controller.term.clearSelection();
  }
  controller.touchSelectionAnchor = anchor;
  controller.touchSelectionStart = {
    x: event.touches[0].clientX,
    y: event.touches[0].clientY
  };
  controller.touchSelectionMoved = false;
  return true;
};

const handleTouchSelectionMove = (controller, event) => {
  if (!controller.selectionMode) return false;

  event.preventDefault();
  event.stopImmediatePropagation();

  if (event.touches.length !== 1) return true;

  if (!controller.touchSelectionAnchor) return true;

  const touch = event.touches[0];
  const current = touchToBufferCell(controller, touch);
  if (!current) return true;

  const start = controller.touchSelectionStart;
  if (start && !controller.touchSelectionMoved) {
    const moved =
      Math.abs(touch.clientX - start.x) > 3 || Math.abs(touch.clientY - start.y) > 3;
    if (!moved) return true;
    controller.touchSelectionMoved = true;
  }

  const range = selectionRange(controller, controller.touchSelectionAnchor, current);
  if (typeof controller.term.select === "function") {
    controller.term.select(range.col, range.row, range.length);
  }
  return true;
};

const handleTouchSelectionEnd = (controller, event) => {
  if (!controller.selectionMode) return false;
  event.preventDefault();
  event.stopImmediatePropagation();
  controller.touchSelectionAnchor = null;
  controller.touchSelectionStart = null;
  controller.touchSelectionMoved = false;
  return true;
};

const installTouchScrolling = (controller, target) => {
  let lastY = 0;
  let moved = false;
  let remainder = 0;

  target.addEventListener(
    "touchstart",
    (event) => {
      if (handleTouchSelectionStart(controller, event)) return;
      if (event.touches.length !== 1) return;
      lastY = event.touches[0].clientY;
      moved = false;
      remainder = 0;
      blurTerminalInput(controller);
    },
    { passive: false, capture: true }
  );

  target.addEventListener(
    "touchmove",
    (event) => {
      if (handleTouchSelectionMove(controller, event)) return;
      if (event.touches.length !== 1) return;
      const nextY = event.touches[0].clientY;
      const deltaY = nextY - lastY;
      lastY = nextY;
      if (Math.abs(deltaY) > 2) moved = true;
      if (!moved) return;
      event.preventDefault();
      remainder += deltaY;
      const lineHeight = terminalLineHeight(controller);
      const lines = Math.trunc(remainder / lineHeight);
      if (lines !== 0) {
        controller.callbacks.onScrollGesture(lines)();
        remainder -= lines * lineHeight;
      }
    },
    { passive: false, capture: true }
  );

  target.addEventListener(
    "touchend",
    (event) => {
      handleTouchSelectionEnd(controller, event);
    },
    { passive: false, capture: true }
  );

  target.addEventListener(
    "touchcancel",
    (event) => {
      handleTouchSelectionEnd(controller, event);
    },
    { passive: false, capture: true }
  );
};

const blurTerminalInput = (controller) => {
  const active = document.activeElement;
  if (active && controller.element && controller.element.contains(active)) {
    active.blur();
  }
};

const shouldAutoFocusTerminal = () => {
  if (typeof window.matchMedia !== "function") return true;
  return window.matchMedia("(pointer: fine)").matches;
};

const visibleTerminalText = (controller) => {
  const buffer = controller.term.buffer && controller.term.buffer.active;
  if (!buffer) return "";
  const start = buffer.viewportY || 0;
  const end = Math.min(buffer.length || 0, start + controller.term.rows);
  const lines = [];
  for (let index = start; index < end; index += 1) {
    const line = buffer.getLine(index);
    lines.push(line ? line.translateToString(true) : "");
  }
  while (lines.length > 0 && lines[lines.length - 1] === "") {
    lines.pop();
  }
  return lines.join("\n");
};

const fallbackClipboardWrite = (text) =>
  new Promise((resolve, reject) => {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "true");
    textarea.style.position = "fixed";
    textarea.style.left = "-10000px";
    textarea.style.top = "0";
    document.body.appendChild(textarea);
    textarea.select();
    try {
      if (document.execCommand("copy")) {
        resolve();
      } else {
        reject(new Error("copy command failed"));
      }
    } catch (error) {
      reject(error);
    } finally {
      textarea.remove();
    }
  });

const writeClipboard = async (text) => {
  if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
    await navigator.clipboard.writeText(text);
  } else {
    await fallbackClipboardWrite(text);
  }
};

export const createTerminal = (theme) => (fontSize) => (callbacks) => () => {
  const xterm = globalThis.AgentTerminal;
  const term = new xterm.Terminal({
    cursorBlink: true,
    fontFamily: terminalFontFamily,
    fontSize,
    scrollOnUserInput: false,
    theme: terminalTheme(theme)
  });
  const fit = new xterm.FitAddon();
  term.loadAddon(fit);
  try {
    const unicode = new xterm.Unicode11Addon();
    term.loadAddon(unicode);
    term.unicode.activeVersion = "11";
  } catch (_) {
    // Optional addon; the terminal still works without it.
  }
  try {
    term.loadAddon(
      new xterm.WebLinksAddon(openTerminalLink(callbacks), {
        hover: () => {
          document.documentElement.style.cursor = "pointer";
        },
        leave: () => {
          document.documentElement.style.cursor = "";
        }
      })
    );
  } catch (_) {
    // Optional addon; terminal output remains usable.
  }

  const controller = {
    term,
    fit,
    socket: null,
    element: null,
    fitPending: false,
    fitAgain: false,
    resizeObserver: null,
    resizeListener: null,
    visibilityListener: null,
    pageShowListener: null,
    viewportResizeListener: null,
    selectionMode: false,
    touchSelectionAnchor: null,
    touchSelectionStart: null,
    touchSelectionMoved: false,
    callbacks
  };

  term.onData((data) => {
    sendTerminalData(controller, data);
  });

  term.onResize(({ cols, rows }) => {
    sendResize(controller, cols, rows);
  });

  return controller;
};

export const mountTerminal = (controller) => (elementId) => () => {
  const target = document.getElementById(elementId);
  if (!target) return;
  controller.element = target;
  controller.term.open(target);
  installTouchScrolling(controller, target);
  try {
    const xterm = globalThis.AgentTerminal;
    const webgl = new xterm.WebglAddon();
    webgl.onContextLoss(() => webgl.dispose());
    controller.term.loadAddon(webgl);
  } catch (_) {
    // Canvas rendering is fine when WebGL is unavailable.
  }
  fitTerminal(controller)();
  controller.resizeListener = () => fitTerminal(controller)();
  window.addEventListener("resize", controller.resizeListener);
  if (window.visualViewport) {
    controller.viewportResizeListener = () => fitTerminal(controller)();
    window.visualViewport.addEventListener("resize", controller.viewportResizeListener);
  }
  if (typeof ResizeObserver !== "undefined") {
    controller.resizeObserver = new ResizeObserver(() => fitTerminal(controller)());
    controller.resizeObserver.observe(target);
    if (target.parentElement) controller.resizeObserver.observe(target.parentElement);
  }
  controller.visibilityListener = () => {
    if (!document.hidden) fitTerminal(controller)();
  };
  document.addEventListener("visibilitychange", controller.visibilityListener);
  controller.pageShowListener = () => fitTerminal(controller)();
  window.addEventListener("pageshow", controller.pageShowListener);
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(() => fitTerminal(controller)()).catch(() => {});
  }
};

const openTerminalSocket = (controller, url, label) => {
  controller.term.clear();
  const socket = new WebSocket(url);
  controller.socket = socket;
  socket.binaryType = "arraybuffer";

  socket.onopen = () => {
    controller.callbacks.onOpen(label)();
    if (shouldAutoFocusTerminal()) {
      controller.term.focus();
    } else {
      blurTerminalInput(controller);
    }
    fitTerminal(controller)();
  };

  socket.onmessage = (event) => {
    if (event.data instanceof ArrayBuffer) {
      controller.term.write(new Uint8Array(event.data));
    } else {
      controller.term.write(event.data);
    }
  };

  socket.onclose = () => {
    if (controller.socket !== socket) return;
    controller.socket = null;
    controller.callbacks.onClose();
  };

  socket.onerror = () => {
    if (controller.socket !== socket) return;
    controller.callbacks.onError();
  };
};

export const attachTerminal = (controller) => (url) => (label) => () => {
  disconnectTerminal(controller)();
  openTerminalSocket(controller, url, label);
};

export const replaceTerminalAfterDestructiveClose = (controller) => (url) => (label) => () => {
  abandonTerminal(controller)();
  openTerminalSocket(controller, url, label);
};

export const disconnectTerminal = (controller) => () => {
  if (!controller.socket) return;
  const socket = controller.socket;
  controller.socket = null;
  if (socket.readyState < WebSocket.CLOSING) {
    socket.close();
  }
};

export const abandonTerminal = (controller) => () => {
  controller.socket = null;
};

export const fitTerminal = (controller) => () => {
  scheduleFit(controller);
};

export const sendEscape = (controller) => () => {
  sendTerminalData(controller, "\x1b");
};

export const sendCtrlB = (controller) => () => {
  sendTerminalData(controller, "\x02");
};

export const sendCtrlBCommand = (controller) => () => {
  sendTerminalData(controller, "\x02:");
};

export const sendText = (controller) => (text) => () => {
  sendTerminalData(controller, normalizePasteData(text));
};

export const copySelectionImpl = (controller) => async () => {
  const selection =
    typeof controller.term.getSelection === "function"
      ? controller.term.getSelection()
      : "";
  const text = selection || visibleTerminalText(controller);
  if (!text) return "empty";
  await writeClipboard(text);
  return selection ? "selection" : "screen";
};

export const setSelectionMode = (controller) => (enabled) => () => {
  controller.selectionMode = enabled;
  controller.touchSelectionAnchor = null;
  controller.touchSelectionStart = null;
  controller.touchSelectionMoved = false;
  if (controller.element) {
    controller.element.classList.toggle("select-mode", enabled);
  }
};

export const setTerminalTheme = (controller) => (theme) => () => {
  const next = terminalTheme(theme);
  if (typeof controller.term.setOption === "function") {
    controller.term.setOption("theme", next);
  } else {
    controller.term.options.theme = next;
  }
};

export const setTerminalFontSize = (controller) => (fontSize) => () => {
  if (typeof controller.term.setOption === "function") {
    controller.term.setOption("fontSize", fontSize);
  } else {
    controller.term.options.fontSize = fontSize;
  }
  fitTerminal(controller)();
};
