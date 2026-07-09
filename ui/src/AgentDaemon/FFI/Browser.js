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

const normalizePaste = (paste) => ({
  name: typeof paste?.name === "string" ? paste.name : "",
  body: typeof paste?.body === "string" ? paste.body : "",
  enter: Boolean(paste?.enter)
});

export const loadPastes = (key) => () => {
  try {
    const value = window.localStorage.getItem(key);
    const parsed = value ? JSON.parse(value) : [];
    if (!Array.isArray(parsed)) return [];
    return parsed
      .map(normalizePaste)
      .filter((paste) => paste.name && paste.body);
  } catch (_) {
    return [];
  }
};

export const savePastes = (key) => (pastes) => () => {
  const normalized = Array.isArray(pastes)
    ? pastes.map(normalizePaste).filter((paste) => paste.name && paste.body)
    : [];
  if (normalized.length === 0) {
    window.localStorage.removeItem(key);
  } else {
    window.localStorage.setItem(key, JSON.stringify(normalized));
  }
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
