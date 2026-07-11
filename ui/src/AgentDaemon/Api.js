const readJsonResponse = async (response) => {
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || response.statusText);
  }
  return data;
};

const normalizeSession = (session) => ({
  id: session.id || session.Id || "",
  state: session.state || session.State || "?",
  tmuxName: session.tmuxName || session.TmuxName || "",
  currentPath: session.currentPath || session.CurrentPath || ""
});

const normalizeWindow = (windowInfo) => ({
  index: Number(windowInfo.index ?? windowInfo.Index ?? 0),
  name: windowInfo.name || windowInfo.Name || "",
  active: Boolean(windowInfo.active ?? windowInfo.Active ?? false)
});

export const fetchSessionsImpl = (base) => () =>
  fetch(`${base}/sessions`)
    .then(readJsonResponse)
    .then((sessions) =>
      Array.isArray(sessions) ? sessions.map(normalizeSession) : []
    );

export const fetchWindowsImpl = (base) => (sessionId) => () =>
  fetch(`${base}/sessions/${encodeURIComponent(sessionId)}/windows`)
    .then(readJsonResponse)
    .then((windows) =>
      Array.isArray(windows) ? windows.map(normalizeWindow) : []
    );

export const createWindowImpl = (base) => (sessionId) => () =>
  fetch(`${base}/sessions/${encodeURIComponent(sessionId)}/windows/new`, {
    method: "POST"
  }).then(readJsonResponse).then(normalizeWindow);

export const deleteSessionImpl = (base) => (sessionId) => () =>
  fetch(
    `${base}/sessions/${encodeURIComponent(sessionId)}?confirm=${encodeURIComponent(sessionId)}`,
    { method: "DELETE" }
  ).then(readJsonResponse).then(() => undefined);

const closeCurrentUrl = (base, sessionId, path) =>
  `${base}/sessions/${encodeURIComponent(sessionId)}/${path}`;

const previewCloseCurrent = (base, sessionId, path) =>
  fetch(closeCurrentUrl(base, sessionId, path), {
    method: "POST"
  }).then(readJsonResponse);

const closeCurrent = (base, sessionId, path, confirmation) =>
  fetch(closeCurrentUrl(base, sessionId, path), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ confirmation })
  }).then(readJsonResponse);

export const previewCloseCurrentPaneImpl = (base) => (sessionId) => () =>
  previewCloseCurrent(base, sessionId, "current-pane/close/preview");

export const closeCurrentPaneImpl = (base) => (sessionId) => (confirmation) => () =>
  closeCurrent(base, sessionId, "current-pane/close", confirmation);

export const previewCloseCurrentWindowImpl = (base) => (sessionId) => () =>
  previewCloseCurrent(base, sessionId, "current-window/close/preview");

export const closeCurrentWindowImpl = (base) => (sessionId) => (confirmation) => () =>
  closeCurrent(base, sessionId, "current-window/close", confirmation);

export const selectWindowImpl = (base) => (sessionId) => (index) => () =>
  fetch(`${base}/sessions/${encodeURIComponent(sessionId)}/windows`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ index })
  }).then(readJsonResponse).then(() => undefined);

export const scrollSessionImpl = (base) => (sessionId) => (lines) => () =>
  fetch(`${base}/sessions/${encodeURIComponent(sessionId)}/scroll`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ lines })
  }).then(readJsonResponse).then(() => undefined);

export const liveSessionImpl = (base) => (sessionId) => () =>
  fetch(`${base}/sessions/${encodeURIComponent(sessionId)}/live`, {
    method: "POST"
  }).then(readJsonResponse).then(() => undefined);
