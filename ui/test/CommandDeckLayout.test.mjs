import assert from "node:assert/strict";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
import { mkdirSync } from "node:fs";
import { basename, extname, join, normalize } from "node:path";
import test from "node:test";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const uiBundle = process.env.UI_BUNDLE;
const screenshotDirectory = process.env.COMMAND_DECK_SCREENSHOT_DIR;
const viewports = [
  { width: 390, height: 844 },
  { width: 768, height: 1024 },
  { width: 1024, height: 768 }
];

const contentTypes = {
  ".css": "text/css",
  ".html": "text/html",
  ".js": "text/javascript",
  ".svg": "image/svg+xml",
  ".woff2": "font/woff2"
};

const commandDeckMetrics = () =>
  Array.from(document.querySelectorAll("[data-command-deck-control]")).map((control) => {
    const rect = control.getBoundingClientRect();
    const centreX = rect.left + rect.width / 2;
    const centreY = rect.top + rect.height / 2;
    const hit = document.elementFromPoint(centreX, centreY);
    return {
      label: control.getAttribute("aria-label"),
      rect: {
        bottom: rect.bottom,
        height: rect.height,
        left: rect.left,
        right: rect.right,
        top: rect.top,
        width: rect.width
      },
      intersectsViewport:
        rect.right > 0 &&
        rect.bottom > 0 &&
        rect.left < window.innerWidth &&
        rect.top < window.innerHeight,
      centreHit: hit === control || control.contains(hit),
      hitTag: hit?.tagName ?? null,
      hitLabel: hit?.closest("[aria-label]")?.getAttribute("aria-label") ?? null
    };
  });

const createFixture = async () => {
  assert.ok(uiBundle, "UI_BUNDLE must name the built static UI directory");
  const server = createServer(async (request, response) => {
    const url = new URL(request.url, "http://127.0.0.1");
    if (url.pathname === "/sessions") {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify([{ id: "layout-session", state: "active", tmuxName: "layout" }]));
      return;
    }
    if (url.pathname === "/sessions/layout-session/windows") {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify([{ index: 0, name: "layout", active: true }]));
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
    close: () => new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())))
  };
};

const attachSession = async (page, viewport) => {
  await page.setViewportSize(viewport);
  await page.addInitScript(() => {
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

      send() {}
    }

    window.WebSocket = FixtureWebSocket;
  });
  await page.goto(process.env.COMMAND_DECK_FIXTURE_URL, { waitUntil: "networkidle" });
  await page.waitForFunction(
    () => document.querySelectorAll("[data-command-deck-control]").length === 11
  );
  await page.waitForTimeout(100);
};

test("attached command deck controls remain visible and hittable at touch viewports", async (t) => {
  const fixture = await createFixture();
  const previousFixtureUrl = process.env.COMMAND_DECK_FIXTURE_URL;
  process.env.COMMAND_DECK_FIXTURE_URL = fixture.url;
  // The self-hosted runner's SystemCallFilter denies the zygote capability transition.
  const browser = await chromium.launch({ headless: true, args: ["--no-zygote"] });
  t.after(async () => {
    if (previousFixtureUrl === undefined) delete process.env.COMMAND_DECK_FIXTURE_URL;
    else process.env.COMMAND_DECK_FIXTURE_URL = previousFixtureUrl;
    await browser.close();
    await fixture.close();
  });

  const failures = [];
  for (const viewport of viewports) {
    const page = await browser.newPage({ viewport });
    await attachSession(page, viewport);
    const metrics = await page.evaluate(commandDeckMetrics);
    if (screenshotDirectory) {
      mkdirSync(screenshotDirectory, { recursive: true });
      await page.screenshot({
        path: join(screenshotDirectory, `command-deck-${viewport.width}x${viewport.height}.png`),
        fullPage: false
      });
    }
    const invalidControls = metrics.filter(
      (control) =>
        control.rect.width < 44 ||
        control.rect.height < 44 ||
        !control.intersectsViewport ||
        !control.centreHit
    );
    console.log(JSON.stringify({ viewport, controls: metrics.length, metrics, invalidControls }));
    if (metrics.length !== 11 || invalidControls.length > 0) {
      failures.push({ viewport, controls: metrics.length, invalidControls });
    }
    await page.close();
  }

  assert.deepEqual(failures, []);
});
