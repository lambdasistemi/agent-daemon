import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { basename, extname, join, normalize } from "node:path";
import test from "node:test";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const uiBundle = process.env.UI_BUNDLE;

const contentTypes = {
  ".css": "text/css",
  ".html": "text/html",
  ".js": "text/javascript",
  ".svg": "image/svg+xml",
  ".woff2": "font/woff2"
};

const createFixture = async () => {
  assert.ok(uiBundle, "UI_BUNDLE must name the built static UI directory");
  const server = createServer(async (request, response) => {
    const url = new URL(request.url, "http://127.0.0.1");
    if (url.pathname === "/sessions") {
      response.setHeader("content-type", "application/json");
      response.end(
        JSON.stringify([{ id: "interaction-session", state: "active", tmuxName: "interaction" }])
      );
      return;
    }
    if (url.pathname === "/sessions/interaction-session/windows") {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify([{ index: 0, name: "interaction", active: true }]));
      return;
    }

    const requestedPath = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
    const filePath = normalize(join(uiBundle, requestedPath));
    if (!filePath.startsWith(`${uiBundle}/`) && filePath !== join(uiBundle, "index.html")) {
      response.statusCode = 400;
      response.end("invalid path");
      return;
    }
    try {
      response.setHeader("content-type", contentTypes[extname(filePath)] ?? "application/octet-stream");
      response.end(await readFile(filePath));
    } catch (_) {
      response.statusCode = 404;
      response.end(`not found: ${basename(filePath)}`);
    }
  });

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  return {
    url: `http://127.0.0.1:${port}`,
    close: () =>
      new Promise((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve()))
      )
  };
};

const openTouchTerminal = async (browser, fixtureUrl) => {
  const context = await browser.newContext({
    hasTouch: true,
    viewport: { width: 390, height: 844 }
  });
  const page = await context.newPage();
  await page.addInitScript(() => {
    window.__terminalFrames = [];

    class FixtureWebSocket {
      static OPEN = 1;
      static CLOSING = 2;

      constructor() {
        this.readyState = 0;
        window.setTimeout(() => {
          this.readyState = FixtureWebSocket.OPEN;
          this.onopen?.({});
        }, 0);
      }

      close() {
        this.readyState = 3;
        this.onclose?.({});
      }

      send(payload) {
        const bytes =
          payload instanceof Uint8Array
            ? Array.from(payload)
            : Array.from(new TextEncoder().encode(String(payload)));
        window.__terminalFrames.push(bytes);
      }
    }

    window.WebSocket = FixtureWebSocket;
  });
  await page.goto(fixtureUrl, { waitUntil: "networkidle" });
  await page.getByRole("button", { name: "Tmux", exact: true }).waitFor();
  await page.waitForTimeout(100);
  await page.evaluate(() => {
    window.__terminalFrames = [];
  });
  return { context, page };
};

const terminalDataFrames = (page) =>
  page.evaluate(() => window.__terminalFrames.filter((frame) => frame[0] !== 1));

test("touch command deck sends one terminal command per tap", async (t) => {
  const fixture = await createFixture();
  // The self-hosted runner's SystemCallFilter denies the zygote capability transition.
  const browser = await chromium.launch({ headless: true, args: ["--no-zygote"] });
  t.after(async () => {
    await browser.close();
    await fixture.close();
  });

  await t.test("Tmux plus Up sends one Ctrl-B-prefixed arrow and consumes the latch", async () => {
    const { context, page } = await openTouchTerminal(browser, fixture.url);
    const tmux = page.getByRole("button", { name: "Tmux", exact: true });

    await tmux.tap();
    assert.equal(await tmux.getAttribute("aria-pressed"), "true");
    await page.getByRole("button", { name: "Up", exact: true }).tap();

    assert.deepEqual(await terminalDataFrames(page), [[2, 27, 91, 65]]);
    assert.equal(await tmux.getAttribute("aria-pressed"), "false");

    await page.getByRole("button", { name: "Up", exact: true }).tap();
    assert.deepEqual(await terminalDataFrames(page), [
      [2, 27, 91, 65],
      [27, 91, 65]
    ]);
    await context.close();
  });

  await t.test("each direct command key emits exactly once", async () => {
    const { context, page } = await openTouchTerminal(browser, fixture.url);
    const cases = [
      ["Esc", [27]],
      ["Tab", [9]],
      ["Left", [27, 91, 68]],
      ["Up", [27, 91, 65]],
      ["Down", [27, 91, 66]],
      ["Right", [27, 91, 67]],
      ["Enter", [13]]
    ];

    for (const [label] of cases) {
      await page.getByRole("button", { name: label, exact: true }).tap();
    }

    assert.deepEqual(
      await terminalDataFrames(page),
      cases.map(([, bytes]) => bytes)
    );
    await context.close();
  });

  await t.test("Ctrl, Alt, and Shift are one-shot touch modifiers", async () => {
    const { context, page } = await openTouchTerminal(browser, fixture.url);
    const ctrl = page.getByRole("button", { name: "Ctrl", exact: true });
    const alt = page.getByRole("button", { name: "Alt", exact: true });
    const shift = page.getByRole("button", { name: "Shift", exact: true });

    await shift.tap();
    await page.getByRole("button", { name: "Tab", exact: true }).tap();
    assert.equal(await shift.getAttribute("aria-pressed"), "false");

    await ctrl.tap();
    await page.getByRole("button", { name: "Left", exact: true }).tap();
    assert.equal(await ctrl.getAttribute("aria-pressed"), "false");

    await alt.tap();
    await page.getByRole("button", { name: "Right", exact: true }).tap();
    assert.equal(await alt.getAttribute("aria-pressed"), "false");

    assert.deepEqual(await terminalDataFrames(page), [
      [27, 91, 90],
      [27, 91, 49, 59, 53, 68],
      [27, 91, 49, 59, 51, 67]
    ]);
    await context.close();
  });

  await t.test("keyboard activation remains an accessible single-send fallback", async () => {
    const { context, page } = await openTouchTerminal(browser, fixture.url);
    const escape = page.getByRole("button", { name: "Esc", exact: true });

    await escape.focus();
    await escape.press("Enter");

    assert.deepEqual(await terminalDataFrames(page), [[27]]);
    await context.close();
  });
});
