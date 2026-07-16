import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { basename, extname, join, normalize } from "node:path";
import test from "node:test";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const uiBundle = process.env.UI_BUNDLE;
const fixtureUrl = new URL("../preview/fixture.js", import.meta.url);

const contentTypes = {
  ".css": "text/css",
  ".html": "text/html",
  ".js": "text/javascript",
  ".svg": "image/svg+xml",
  ".woff2": "font/woff2"
};

const createPreview = async () => {
  assert.ok(uiBundle, "UI_BUNDLE must name the built static UI directory");
  const [fixture, productionIndex] = await Promise.all([
    readFile(fixtureUrl),
    readFile(join(uiBundle, "index.html"), "utf8")
  ]);
  const previewIndex = productionIndex.replace(
    /(\s*<script\s+src=["']index\.js[^>]*><\/script>)/,
    '\n  <script src="fixture.js"></script>$1'
  );
  assert.notEqual(previewIndex, productionIndex, "fixture is injected before index.js");
  assert.ok(
    previewIndex.indexOf('src="fixture.js"') < previewIndex.indexOf('src="index.js'),
    "fixture runs before the production application bundle"
  );

  const server = createServer(async (request, response) => {
    const url = new URL(request.url, "http://127.0.0.1");
    if (url.pathname === "/fixture.js") {
      response.setHeader("content-type", "text/javascript");
      response.end(fixture);
      return;
    }
    if (url.pathname === "/" || url.pathname === "/index.html") {
      response.setHeader("content-type", "text/html");
      response.end(previewIndex);
      return;
    }

    const filePath = normalize(join(uiBundle, url.pathname.slice(1)));
    if (!filePath.startsWith(`${uiBundle}/`)) {
      response.statusCode = 400;
      response.end("invalid path");
      return;
    }
    try {
      response.setHeader(
        "content-type",
        contentTypes[extname(filePath)] ?? "application/octet-stream"
      );
      response.end(await readFile(filePath));
    } catch (_) {
      response.statusCode = 404;
      response.end(`not found: ${basename(filePath)}`);
    }
  });

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  return {
    close: () =>
      new Promise((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve()))
      ),
    url: `http://127.0.0.1:${port}`
  };
};

const openMenu = async (page, buttonName, menuSelector) => {
  await page.getByRole("button", { name: buttonName, exact: true }).tap();
  const menu = page.locator(`${menuSelector}:visible`);
  await menu.waitFor({ state: "visible" });
  return menu;
};

test("PR preview fixture illustrates the complete session and window flow", async (t) => {
  const preview = await createPreview();
  const browser = await chromium.launch({ headless: true, args: ["--no-zygote"] });
  const context = await browser.newContext({
    viewport: { width: 768, height: 1024 },
    hasTouch: true,
    isMobile: false
  });
  const page = await context.newPage();
  const browserErrors = [];
  page.on("pageerror", (error) => browserErrors.push(`pageerror: ${error.message}`));
  page.on("console", (message) => {
    if (message.type() === "error") browserErrors.push(`console.error: ${message.text()}`);
  });
  t.after(async () => {
    await context.close();
    await browser.close();
    await preview.close();
  });

  await page.goto(preview.url, { waitUntil: "networkidle" });
  await page
    .getByText("Illustrative preview data — not connected to a daemon.", { exact: true })
    .waitFor({ state: "visible" });
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".session-menu-item").length >= 4 &&
      document.querySelectorAll(".window-menu-item").length >= 10
  );

  let menu = await openMenu(page, "Switch session", ".session-menu");
  assert.ok(await menu.locator(".session-menu-item").count() >= 4, "multiple sessions load");
  await menu.locator(".context-menu-close").tap();
  await menu.waitFor({ state: "hidden" });

  menu = await openMenu(page, "Switch session", ".session-menu");
  const nextSession = menu.locator(".session-menu-item").nth(2);
  const nextSessionName = (await nextSession.locator(".session-name").textContent()).trim();
  await nextSession.tap();
  await menu.waitFor({ state: "hidden" });
  await page.waitForFunction(
    (name) => document.querySelector(".session-label")?.textContent?.trim() === name,
    nextSessionName
  );

  menu = await openMenu(page, "Switch tmux window", ".window-menu");
  assert.ok(await menu.locator(".window-menu-item").count() >= 10, "many windows load");
  const nextWindow = menu.locator(".window-menu-item").nth(2);
  const nextWindowName = (await nextWindow.textContent()).trim();
  await nextWindow.tap();
  await menu.waitFor({ state: "hidden" });
  await page.waitForFunction(
    (name) => document.querySelector(".window-label")?.textContent?.trim() === name,
    nextWindowName
  );

  menu = await openMenu(page, "Switch tmux window", ".window-menu");
  await page
    .locator(".context-menu-layer:not(.hidden) .context-menu-backdrop")
    .tap({ position: { x: 2, y: 2 } });
  await menu.waitFor({ state: "hidden" });

  menu = await openMenu(page, "Switch tmux window", ".window-menu");
  const countBeforeCreate = await menu.locator(".window-menu-item").count();
  await menu.getByRole("button", { name: "New window", exact: true }).tap();
  await menu.waitFor({ state: "hidden" });
  menu = await openMenu(page, "Switch tmux window", ".window-menu");
  await page.waitForFunction(
    (expected) => document.querySelectorAll(".window-menu-item").length === expected,
    countBeforeCreate + 1
  );
  assert.equal(
    await menu.locator('.window-menu-item[aria-current="true"]').count(),
    1,
    "new window becomes the active window"
  );
  await menu.locator(".context-menu-close").tap();

  await page.waitForTimeout(100);
  assert.deepEqual(browserErrors, []);
});
