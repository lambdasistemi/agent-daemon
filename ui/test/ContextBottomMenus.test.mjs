import assert from "node:assert/strict";
import { mkdirSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { basename, extname, join, normalize } from "node:path";
import test from "node:test";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const uiBundle = process.env.UI_BUNDLE;
const screenshotDirectory = process.env.CONTEXT_MENU_SCREENSHOT_DIR;
const viewports = [
  { width: 390, height: 844 },
  { width: 768, height: 1024 },
  { width: 1024, height: 768 }
];

const sessions = Array.from({ length: 20 }, (_, index) => ({
  id: `context-session-${index + 1}`,
  state: index === 0 ? "active" : "detached",
  tmuxName: `context-${index + 1}`,
  currentPath: `/workspace/context-${index + 1}`
}));

const windows = Array.from({ length: 18 }, (_, index) => ({
  index,
  name: `window-${String(index + 1).padStart(2, "0")}`,
  active: index === 0
}));

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
    if (request.method === "GET" && url.pathname === "/sessions") {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify(sessions));
      return;
    }
    if (
      request.method === "GET" &&
      /^\/sessions\/[^/]+\/windows$/.test(url.pathname)
    ) {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify(windows));
      return;
    }
    if (
      request.method === "POST" &&
      /^\/sessions\/[^/]+\/windows$/.test(url.pathname)
    ) {
      response.setHeader("content-type", "application/json");
      response.end("{}");
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

const installWebSocketFixture = async (page) => {
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
};

const menuContract = async (page, viewport, kind) => {
  const title = kind === "session" ? "Sessions" : "Windows";
  const titleId = kind === "session" ? "sessions-menu-title" : "windows-menu-title";
  const switchLabel = kind === "session" ? "Switch session" : "Switch tmux window";
  const otherSwitchLabel = kind === "session" ? "Switch tmux window" : "Switch session";
  const sheetSelector = `.${kind}-menu`;
  const rowSelector = `.${kind}-menu-item`;
  const switcher = page.getByRole("button", { name: switchLabel, exact: true });
  const openMenu = async () => {
    await switcher.tap();
    await page.waitForFunction(
      (label) =>
        document.querySelector(`button[aria-label="${label}"]`)?.getAttribute("aria-expanded") ===
        "true",
      switchLabel,
      { timeout: 10000 }
    );
  };

  await openMenu();
  const sheet = page.locator(`${sheetSelector}:visible`);
  const layer = page.locator(`.context-menu-layer:visible`);
  const backdrop = layer.locator(".context-menu-backdrop");
  const header = sheet.locator(".context-menu-header");
  const close = sheet.locator(`.context-menu-close[aria-label="Close ${title} menu"]`);
  const choices = sheet.locator(".context-menu-choices");

  await assert.doesNotReject(
    sheet.locator(`h2#${titleId}`).waitFor({ state: "visible", timeout: 10000 }),
    `${title} menu exposes a visible title`
  );
  assert.equal((await sheet.locator(`h2#${titleId}`).textContent()).trim(), title);
  assert.equal(await sheet.getAttribute("aria-labelledby"), titleId);
  await assert.doesNotReject(
    backdrop.waitFor({ state: "visible", timeout: 10000 }),
    `${title} menu exposes a visible backdrop`
  );

  if (screenshotDirectory) {
    mkdirSync(screenshotDirectory, { recursive: true });
    await page.screenshot({
      path: join(
        screenshotDirectory,
        `${kind}-menu-${viewport.width}x${viewport.height}.png`
      ),
      fullPage: false
    });
  }

  const geometry = await page.evaluate(
    ({ sheetSelector: currentSheetSelector }) => {
      const currentSheet = document.querySelector(`${currentSheetSelector}:not(.hidden)`);
      const currentBackdrop = document.querySelector(
        ".context-menu-layer:not(.hidden) .context-menu-backdrop"
      );
      const dock = document.querySelector(".action-dock");
      assertElement(currentSheet, "open context menu sheet");
      assertElement(currentBackdrop, "open context menu backdrop");
      assertElement(dock, "action dock");

      const sheetRect = currentSheet.getBoundingClientRect();
      const backdropRect = currentBackdrop.getBoundingClientRect();
      const dockRect = dock.getBoundingClientRect();
      const overlapY = Math.min(sheetRect.bottom - 4, dockRect.top + 4);
      const overlapX = sheetRect.left + sheetRect.width / 2;
      const hit = document.elementFromPoint(overlapX, overlapY);
      const safeProbe = document.createElement("div");
      safeProbe.style.position = "fixed";
      safeProbe.style.bottom = "var(--safe-bottom)";
      document.body.append(safeProbe);
      const safeBottom = Number.parseFloat(getComputedStyle(safeProbe).bottom) || 0;
      safeProbe.remove();

      return {
        backdrop: {
          bottom: backdropRect.bottom,
          left: backdropRect.left,
          right: backdropRect.right,
          top: backdropRect.top
        },
        dockTop: dockRect.top,
        hitInsideSheet: hit === currentSheet || currentSheet.contains(hit),
        safeBottom,
        sheetBottom: sheetRect.bottom,
        viewport: { height: innerHeight, width: innerWidth }
      };

      function assertElement(element, description) {
        if (!element) throw new Error(`missing ${description}`);
      }
    },
    { sheetSelector }
  );

  assert.ok(Math.abs(geometry.backdrop.left) <= 1, `${title} backdrop starts at viewport left`);
  assert.ok(Math.abs(geometry.backdrop.top) <= 1, `${title} backdrop starts at viewport top`);
  assert.ok(
    Math.abs(geometry.backdrop.right - geometry.viewport.width) <= 1,
    `${title} backdrop reaches viewport right`
  );
  assert.ok(
    Math.abs(geometry.backdrop.bottom - geometry.viewport.height) <= 1,
    `${title} backdrop reaches viewport bottom`
  );
  assert.ok(
    Math.abs(geometry.sheetBottom - (geometry.viewport.height - geometry.safeBottom)) <= 1,
    `${title} sheet is anchored to the viewport bottom above the safe area`
  );
  assert.ok(geometry.sheetBottom > geometry.dockTop, `${title} sheet visually overlays the dock`);
  assert.ok(geometry.hitInsideSheet, `${title} sheet owns the hit layer over the dock`);

  const headerBefore = await header.boundingBox();
  await choices.evaluate((element) => {
    element.scrollTop = element.scrollHeight;
  });
  await page.waitForTimeout(50);
  const scrollTop = await choices.evaluate((element) => element.scrollTop);
  const headerAfter = await header.boundingBox();
  assert.ok(scrollTop > 0, `${title} choices scroll independently`);
  assert.ok(headerBefore && headerAfter, `${title} header stays visible while choices scroll`);
  assert.ok(
    Math.abs(headerBefore.y - headerAfter.y) <= 1,
    `${title} header remains fixed while choices scroll`
  );
  await assert.doesNotReject(close.waitFor({ state: "visible" }), `${title} close stays visible`);

  const controls = sheet.locator(`${rowSelector}, .context-menu-close`);
  const controlCount = await controls.count();
  assert.ok(controlCount > 1, `${title} exposes close and choice controls`);
  for (let index = 0; index < controlCount; index += 1) {
    const control = controls.nth(index);
    await control.scrollIntoViewIfNeeded();
    const metrics = await control.evaluate((element) => {
      const rect = element.getBoundingClientRect();
      const hit = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
      return {
        centreHit: hit === element || element.contains(hit),
        height: rect.height,
        label: element.getAttribute("aria-label") ?? element.textContent.trim(),
        width: rect.width
      };
    });
    assert.ok(metrics.width >= 44, `${title} ${metrics.label} is at least 44px wide`);
    assert.ok(metrics.height >= 44, `${title} ${metrics.label} is at least 44px high`);
    assert.ok(metrics.centreHit, `${title} ${metrics.label} owns its centre hit point`);
  }

  const activeRows = sheet.locator(
    `${rowSelector}[aria-current="true"], ${rowSelector}[aria-selected="true"]`
  );
  assert.equal(await activeRows.count(), 1, `${title} exposes exactly one accessible active row`);

  if (kind === "window") {
    const firstChoice = choices.locator("button").first();
    assert.equal((await firstChoice.textContent()).trim(), "New window", "New window stays first");
    assert.ok(
      await firstChoice.evaluate((element) => element.classList.contains("window-menu-action")),
      "New window remains a separated action"
    );
  }

  await close.tap();
  await assert.doesNotReject(sheet.waitFor({ state: "hidden" }), `${title} close dismisses`);

  await openMenu();
  await backdrop.tap({ position: { x: 2, y: 2 } });
  await assert.doesNotReject(sheet.waitFor({ state: "hidden" }), `${title} backdrop dismisses`);

  await openMenu();
  await page
    .getByRole("button", { name: otherSwitchLabel, exact: true })
    .evaluate((element) => element.click());
  await assert.doesNotReject(sheet.waitFor({ state: "hidden" }), `opening the other menu closes ${title}`);
  const otherKind = kind === "session" ? "window" : "session";
  const otherSheet = page.locator(`.${otherKind}-menu:visible`);
  await assert.doesNotReject(otherSheet.waitFor({ state: "visible" }), "the other menu opens");
  await otherSheet.locator(".context-menu-close").tap();

  await openMenu();
  await sheet
    .locator(`${rowSelector}[aria-current="true"], ${rowSelector}[aria-selected="true"]`)
    .tap();
  await assert.doesNotReject(sheet.waitFor({ state: "hidden" }), `${title} selection keeps close behavior`);
};

test("touch Session and Window selectors are viewport-bottom context menus", async (t) => {
  const fixture = await createFixture();
  const browser = await chromium.launch({ headless: true, args: ["--no-zygote"] });
  t.after(async () => {
    await browser.close();
    await fixture.close();
  });

  for (const viewport of viewports) {
    for (const kind of ["session", "window"]) {
      await t.test(`${kind} menu at ${viewport.width}x${viewport.height}`, async (subtest) => {
        const context = await browser.newContext({ viewport, hasTouch: true, isMobile: false });
        const page = await context.newPage();
        subtest.after(() => context.close());
        await installWebSocketFixture(page);
        await page.goto(fixture.url, { waitUntil: "networkidle" });
        await page.waitForFunction(
          () =>
            document.querySelectorAll(".session-menu-item").length >= 2 &&
            document.querySelectorAll(".window-menu-item").length >= 12
        );
        const coarsePointer = await page.evaluate(() => matchMedia("(pointer: coarse)").matches);
        if (viewport.width === 1024 && !coarsePointer) {
          subtest.skip("Chromium context does not expose coarse pointer emulation");
          return;
        }
        await menuContract(page, viewport, kind);
      });
    }
  }
});
