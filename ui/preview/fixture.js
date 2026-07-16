(() => {
  "use strict";

  const sessions = [
    {
      id: "preview-roadmap",
      state: "active",
      tmuxName: "Roadmap review",
      currentPath: "/workspace/tmux-ws"
    },
    {
      id: "preview-release",
      state: "detached",
      tmuxName: "Release rehearsal",
      currentPath: "/workspace/release"
    },
    {
      id: "preview-incident",
      state: "detached",
      tmuxName: "Payments incident",
      currentPath: "/workspace/incident-response"
    },
    {
      id: "preview-documentation",
      state: "detached",
      tmuxName: "Documentation pass",
      currentPath: "/workspace/docs"
    },
    {
      id: "preview-experiments",
      state: "detached",
      tmuxName: "UI experiments",
      currentPath: "/workspace/ui-lab"
    }
  ];

  const windowNames = [
    "editor",
    "tests",
    "daemon-logs",
    "ui-preview",
    "release-notes",
    "nix-shell",
    "api-client",
    "metrics",
    "documentation",
    "review",
    "scratch",
    "monitor"
  ];
  const windowsBySession = new Map(
    sessions.map((session) => [
      session.id,
      windowNames.map((name, index) => ({ index, name, active: index === 0 }))
    ])
  );

  const jsonResponse = (value) =>
    new Response(JSON.stringify(value), {
      headers: { "content-type": "application/json" },
      status: 200
    });

  const requestDetails = (input, init) => {
    const request = input instanceof Request ? input : null;
    return {
      body: init?.body ?? request?.body,
      method: String(init?.method ?? request?.method ?? "GET").toUpperCase(),
      url: new URL(request?.url ?? String(input), window.location.href)
    };
  };

  const sessionWindowsMatch = (pathname) =>
    pathname.match(/^\/sessions\/([^/]+)\/windows$/);
  const newWindowMatch = (pathname) =>
    pathname.match(/^\/sessions\/([^/]+)\/windows\/new$/);
  const liveOrScrollMatch = (pathname) =>
    pathname.match(/^\/sessions\/([^/]+)\/(live|scroll)$/);

  const originalFetch = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const request = requestDetails(input, init);
    if (request.url.origin !== window.location.origin) return originalFetch(input, init);

    if (request.method === "GET" && request.url.pathname === "/sessions") {
      return jsonResponse(sessions);
    }

    const windowsMatch = sessionWindowsMatch(request.url.pathname);
    if (request.method === "GET" && windowsMatch) {
      return jsonResponse(windowsBySession.get(decodeURIComponent(windowsMatch[1])) ?? []);
    }
    if (request.method === "POST" && windowsMatch) {
      const sessionId = decodeURIComponent(windowsMatch[1]);
      const windows = windowsBySession.get(sessionId) ?? [];
      const payload = typeof request.body === "string" ? JSON.parse(request.body) : {};
      for (const windowInfo of windows) windowInfo.active = windowInfo.index === payload.index;
      return jsonResponse({});
    }

    const createMatch = newWindowMatch(request.url.pathname);
    if (request.method === "POST" && createMatch) {
      const sessionId = decodeURIComponent(createMatch[1]);
      const windows = windowsBySession.get(sessionId) ?? [];
      const index = windows.reduce((maximum, windowInfo) =>
        Math.max(maximum, windowInfo.index), -1) + 1;
      for (const windowInfo of windows) windowInfo.active = false;
      const created = { index, name: `new-window-${index}`, active: true };
      windows.push(created);
      windowsBySession.set(sessionId, windows);
      return jsonResponse(created);
    }

    if (request.method === "POST" && liveOrScrollMatch(request.url.pathname)) {
      return jsonResponse({});
    }

    return originalFetch(input, init);
  };

  const NativeWebSocket = window.WebSocket;
  const isPreviewTerminal = (url) => {
    const target = new URL(String(url), window.location.href.replace(/^http/, "ws"));
    return (
      target.host === window.location.host &&
      /^\/sessions\/[^/]+\/terminal$/.test(target.pathname)
    );
  };

  class PreviewWebSocket {
    static CONNECTING = 0;
    static OPEN = 1;
    static CLOSING = 2;
    static CLOSED = 3;

    constructor(url, protocols) {
      if (!isPreviewTerminal(url)) return new NativeWebSocket(url, protocols);
      this.binaryType = "blob";
      this.bufferedAmount = 0;
      this.extensions = "";
      this.protocol = "";
      this.readyState = PreviewWebSocket.CONNECTING;
      this.url = String(url);
      this.listeners = new Map();
      window.setTimeout(() => {
        if (this.readyState !== PreviewWebSocket.CONNECTING) return;
        this.readyState = PreviewWebSocket.OPEN;
        this.dispatch("open", new Event("open"));
        this.dispatch(
          "message",
          new MessageEvent("message", {
            data: "\u001b[36mIllustrative terminal\u001b[0m\r\n$ nix develop\r\n"
          })
        );
      }, 0);
    }

    addEventListener(type, listener) {
      const listeners = this.listeners.get(type) ?? new Set();
      listeners.add(listener);
      this.listeners.set(type, listeners);
    }

    removeEventListener(type, listener) {
      this.listeners.get(type)?.delete(listener);
    }

    dispatch(type, event) {
      this[`on${type}`]?.call(this, event);
      for (const listener of this.listeners.get(type) ?? []) listener.call(this, event);
    }

    send() {}

    close() {
      if (this.readyState >= PreviewWebSocket.CLOSING) return;
      this.readyState = PreviewWebSocket.CLOSING;
      window.setTimeout(() => {
        this.readyState = PreviewWebSocket.CLOSED;
        this.dispatch("close", new Event("close"));
      }, 0);
    }
  }

  window.WebSocket = PreviewWebSocket;

  const notice = document.createElement("div");
  notice.dataset.previewFixtureNotice = "";
  notice.setAttribute("role", "status");
  notice.textContent = "Illustrative preview data — not connected to a daemon.";
  notice.style.cssText = [
    "background:#fef3c7",
    "border-bottom:1px solid #d97706",
    "color:#78350f",
    "font:600 14px/1.4 system-ui,sans-serif",
    "padding:8px 16px",
    "text-align:center"
  ].join(";");
  document.body.prepend(notice);
})();
