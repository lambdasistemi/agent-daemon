import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { basename, extname, join, normalize } from "node:path";
import test from "node:test";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const uiBundle = process.env.UI_BUNDLE;
const viewports = [
  { label: "small touch", width: 390, height: 844 },
  { label: "portrait tablet", width: 768, height: 1024 },
  { label: "landscape tablet", width: 1024, height: 768 }
];
const latchLabels = ["Ctrl", "Alt", "Shift", "Tmux"];
const directKeyCases = [
  ["Esc", [27]],
  ["Tab", [9]],
  ["Left", [27, 91, 68]],
  ["Up", [27, 91, 65]],
  ["Down", [27, 91, 66]],
  ["Right", [27, 91, 67]],
  ["Enter", [13]]
];
const modifierCases = [
  [["Shift"], [27, 91, 49, 59, 50, 65]],
  [["Alt"], [27, 91, 49, 59, 51, 65]],
  [["Shift", "Alt"], [27, 91, 49, 59, 52, 65]],
  [["Ctrl"], [27, 91, 49, 59, 53, 65]],
  [["Shift", "Ctrl"], [27, 91, 49, 59, 54, 65]],
  [["Alt", "Ctrl"], [27, 91, 49, 59, 55, 65]],
  [["Shift", "Alt", "Ctrl"], [27, 91, 49, 59, 56, 65]],
  [["Tmux"], [2, 27, 91, 65]],
  [["Tmux", "Shift"], [2, 27, 91, 49, 59, 50, 65]],
  [["Tmux", "Alt"], [2, 27, 91, 49, 59, 51, 65]],
  [["Tmux", "Shift", "Alt"], [2, 27, 91, 49, 59, 52, 65]],
  [["Tmux", "Ctrl"], [2, 27, 91, 49, 59, 53, 65]],
  [["Tmux", "Shift", "Ctrl"], [2, 27, 91, 49, 59, 54, 65]],
  [["Tmux", "Alt", "Ctrl"], [2, 27, 91, 49, 59, 55, 65]],
  [["Tmux", "Shift", "Alt", "Ctrl"], [2, 27, 91, 49, 59, 56, 65]]
];
const nativeInputCases = [
  [["Ctrl"], "c", [3]],
  [["Alt"], "x", [27, 120]],
  [["Shift"], "x", [88]],
  [["Tmux"], "b", [2, 98]],
  [["Tmux", "Ctrl", "Alt", "Shift"], "z", [2, 27, 26]]
];

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

const openTouchTerminal = async (browser, fixtureUrl, viewport) => {
  const context = await browser.newContext({
    hasTouch: true,
    viewport
  });
  const page = await context.newPage();
  const browserErrors = [];
  page.on("pageerror", (error) => browserErrors.push(`pageerror: ${error.message}`));
  page.on("console", (message) => {
    if (message.type() === "error") browserErrors.push(`console.error: ${message.text()}`);
  });
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
  return { browserErrors, context, page };
};

const terminalDataFrames = (page) =>
  page.evaluate(() => window.__terminalFrames.filter((frame) => frame[0] !== 1));

const clearTerminalData = (page) =>
  page.evaluate(() => {
    window.__terminalFrames = [];
  });

const commandButton = (page, label) =>
  page.getByRole("button", { name: label, exact: true });

const withTouchTerminal = async (browser, fixtureUrl, viewport, scenario) => {
  const { browserErrors, context, page } = await openTouchTerminal(
    browser,
    fixtureUrl,
    viewport
  );
  try {
    await scenario(page);
    assert.deepEqual(browserErrors, []);
  } finally {
    await context.close();
  }
};

const pointerEvent = (pointerId, buttons) => ({
  button: 0,
  buttons,
  isPrimary: true,
  pointerId,
  pointerType: "touch"
});

test("command deck is reliable without a physical keyboard or mouse", async (t) => {
  const fixture = await createFixture();
  // The self-hosted runner's SystemCallFilter denies the zygote capability transition.
  const browser = await chromium.launch({ headless: true, args: ["--no-zygote"] });
  t.after(async () => {
    await browser.close();
    await fixture.close();
  });

  for (const viewport of viewports) {
    const dimensions = { width: viewport.width, height: viewport.height };

    await t.test(`${viewport.label}: every direct key sends exactly once`, async () => {
      await withTouchTerminal(browser, fixture.url, dimensions, async (page) => {
        for (const [label] of directKeyCases) {
          await commandButton(page, label).tap();
        }

        assert.deepEqual(
          await terminalDataFrames(page),
          directKeyCases.map(([, bytes]) => bytes)
        );
      });
    });

    await t.test(`${viewport.label}: all modifier combinations are one-shot`, async () => {
      await withTouchTerminal(browser, fixture.url, dimensions, async (page) => {
        for (const [labels, expected] of modifierCases) {
          await clearTerminalData(page);
          for (const label of labels) {
            const latch = commandButton(page, label);
            await latch.tap();
            assert.equal(await latch.getAttribute("aria-pressed"), "true");
          }

          await commandButton(page, "Up").tap();
          assert.deepEqual(await terminalDataFrames(page), [expected]);
          for (const label of latchLabels) {
            assert.equal(await commandButton(page, label).getAttribute("aria-pressed"), "false");
          }

          await commandButton(page, "Up").tap();
          assert.deepEqual(await terminalDataFrames(page), [expected, [27, 91, 65]]);
        }
      });
    });

    await t.test(`${viewport.label}: every latch can be cancelled without input`, async () => {
      await withTouchTerminal(browser, fixture.url, dimensions, async (page) => {
        for (const label of latchLabels) {
          await clearTerminalData(page);
          const latch = commandButton(page, label);
          await latch.tap();
          assert.equal(await latch.getAttribute("aria-pressed"), "true");
          await latch.tap();
          assert.equal(await latch.getAttribute("aria-pressed"), "false");
          assert.deepEqual(await terminalDataFrames(page), []);
        }
      });
    });

    await t.test(`${viewport.label}: arrow repeat stops on release, cancel, leave, and blur`, async () => {
      await withTouchTerminal(browser, fixture.url, dimensions, async (page) => {
        const up = commandButton(page, "Up");
        await up.dispatchEvent("pointerdown", pointerEvent(41, 1));
        await page.waitForTimeout(280);
        const heldFrames = await terminalDataFrames(page);
        assert.ok(heldFrames.length >= 2, "held arrow repeats after its initial input");
        await up.dispatchEvent("pointerup", pointerEvent(41, 0));
        await page.waitForTimeout(300);
        assert.deepEqual(await terminalDataFrames(page), heldFrames);

        await clearTerminalData(page);
        const right = commandButton(page, "Right");
        await right.dispatchEvent("pointerdown", pointerEvent(42, 1));
        await page.waitForTimeout(30);
        await right.dispatchEvent("pointercancel", pointerEvent(42, 0));
        await page.waitForTimeout(300);
        assert.deepEqual(await terminalDataFrames(page), [[27, 91, 67]]);

        await clearTerminalData(page);
        const down = commandButton(page, "Down");
        await down.dispatchEvent("pointerdown", pointerEvent(43, 1));
        await page.waitForTimeout(30);
        await down.dispatchEvent("pointerleave", pointerEvent(43, 0));
        await page.waitForTimeout(300);
        assert.deepEqual(await terminalDataFrames(page), [[27, 91, 66]]);

        await clearTerminalData(page);
        const left = commandButton(page, "Left");
        await left.dispatchEvent("pointerdown", pointerEvent(44, 1));
        await page.waitForTimeout(30);
        await page.evaluate(() => window.dispatchEvent(new Event("blur")));
        await page.waitForTimeout(300);
        assert.deepEqual(await terminalDataFrames(page), [[27, 91, 68]]);
      });
    });
  }

  await t.test("keyboard and assistive activation send every direct key once", async () => {
    const viewport = viewports[1];
    await withTouchTerminal(
      browser,
      fixture.url,
      { width: viewport.width, height: viewport.height },
      async (page) => {
        for (const [label] of directKeyCases) {
          const control = commandButton(page, label);
          await control.focus();
          await control.press("Enter");
        }

        assert.deepEqual(
          await terminalDataFrames(page),
          directKeyCases.map(([, bytes]) => bytes)
        );

        await clearTerminalData(page);
        for (const [label] of directKeyCases) {
          await commandButton(page, label).evaluate((element) => element.click());
        }
        assert.deepEqual(
          await terminalDataFrames(page),
          directKeyCases.map(([, bytes]) => bytes)
        );
      }
    );
  });

  await t.test("touch latches modify native virtual-keyboard input exactly once", async () => {
    const viewport = viewports[1];
    await withTouchTerminal(
      browser,
      fixture.url,
      { width: viewport.width, height: viewport.height },
      async (page) => {
        const terminalInput = page.locator(".xterm-helper-textarea");
        await terminalInput.waitFor({ state: "attached" });

        for (const [labels, key, expected] of nativeInputCases) {
          await clearTerminalData(page);
          for (const label of labels) {
            await commandButton(page, label).tap();
          }
          await terminalInput.focus();
          await page.keyboard.press(key);

          assert.deepEqual(await terminalDataFrames(page), [expected]);
          for (const label of latchLabels) {
            assert.equal(await commandButton(page, label).getAttribute("aria-pressed"), "false");
          }
        }
      }
    );
  });
});
