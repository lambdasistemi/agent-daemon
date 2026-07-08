const trimTrailingSlash = (value) => value.replace(/\/$/, "");

const apiBaseFrom = (value) => {
  const server = value.trim();
  if (!server) return window.location.origin;
  return trimTrailingSlash(server.startsWith("http") ? server : `http://${server}`);
};

const wsBaseFrom = (value) => {
  const server = value.trim();
  if (!server) {
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    return `${proto}//${window.location.host}`;
  }
  const proto = server.startsWith("https") ? "wss:" : "ws:";
  return `${proto}//${trimTrailingSlash(server.replace(/^https?:\/\//, ""))}`;
};

export const loadItem = (key) => () =>
  window.localStorage.getItem(key) || "";

export const saveItem = (key) => (value) => () => {
  if (value) window.localStorage.setItem(key, value);
  else window.localStorage.removeItem(key);
};

export const apiBase = (server) => () => apiBaseFrom(server);

export const sessionTerminalWsUrl = (server) => (sessionId) => () =>
  `${wsBaseFrom(server)}/sessions/${encodeURIComponent(sessionId)}/terminal`;

export const renderIcons = () => {
  if (!globalThis.lucide || typeof globalThis.lucide.createElement !== "function") {
    return;
  }
  for (const slot of document.querySelectorAll("[data-lucide-slot]")) {
    const name = slot.dataset.lucideSlot;
    if (slot.dataset.renderedIcon === name && slot.firstElementChild) continue;
    slot.replaceChildren();
    const iconName = name
      .split("-")
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join("");
    const icon = globalThis.lucide.icons[iconName];
    if (icon) {
      const svg = globalThis.lucide.createElement(icon);
      svg.classList.add("lucide");
      svg.setAttribute("aria-hidden", "true");
      slot.appendChild(svg);
      slot.dataset.renderedIcon = name;
    } else {
      slot.textContent = slot.dataset.fallback || "";
    }
  }
};

export const afterRender = (effect) => () => {
  window.requestAnimationFrame(() => effect());
};

export const setDocumentTheme = (theme) => () => {
  document.documentElement.dataset.theme = theme;
};
