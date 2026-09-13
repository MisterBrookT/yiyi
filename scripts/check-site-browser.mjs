#!/usr/bin/env node
// Dependency-free Chrome acceptance: real layout, images, focus, and media queries.
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, writeFile, mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, dirname, extname, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../docs/site");
const output =
  process.env.YIYI_SITE_CHECK_DIR ||
  (await mkdtemp(`${tmpdir()}/yiyi-site-review-`));
await mkdir(output, { recursive: true });
const profile = await mkdtemp(`${tmpdir()}/yiyi-chrome-`);
const server = createServer(async (request, response) => {
  const path = resolve(
    root,
    "." +
      decodeURIComponent(
        new URL(request.url, "http://localhost").pathname,
      ).replace(/\/$/, "/index.html"),
  );
  if (!path.startsWith(root + sep)) {
    response.writeHead(403).end();
    return;
  }
  try {
    const mime = {
      ".html": "text/html",
      ".css": "text/css",
      ".png": "image/png",
    };
    response.setHeader(
      "Content-Type",
      mime[extname(path)] || "application/octet-stream",
    );
    response.end(await readFile(path));
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const chrome = spawn(
  process.env.CHROME_BIN ||
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  [
    "--headless",
    "--disable-gpu",
    "--disable-background-networking",
    "--no-first-run",
    "--no-default-browser-check",
    "--remote-debugging-port=0",
    `--user-data-dir=${profile}`,
    "about:blank",
  ],
);
let socket;
const watchdog = setTimeout(() => {
  console.error("Browser check timed out");
  chrome.kill();
  server.close();
  process.exitCode = 1;
}, 60000);
try {
  const endpoint = await new Promise((resolve, reject) => {
    chrome.on("error", reject);
    chrome.stderr.on("data", (data) => {
      const match = data.toString().match(/DevTools listening on (ws:\/\/\S+)/);
      if (match) resolve(match[1]);
    });
    chrome.on("exit", (code) => reject(new Error(`Chrome exited: ${code}`)));
  });
  socket = new WebSocket(endpoint);
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve);
    socket.addEventListener("error", reject);
  });
  let next = 0;
  const pending = new Map();
  socket.addEventListener("message", ({ data }) => {
    const result = JSON.parse(data);
    const callbacks = pending.get(result.id);
    if (callbacks) {
      pending.delete(result.id);
      result.error
        ? callbacks.reject(new Error(result.error.message))
        : callbacks.resolve(result.result);
    }
  });
  function call(method, params = {}, sessionId) {
    return new Promise((resolve, reject) => {
      const id = ++next;
      pending.set(id, { resolve, reject });
      socket.send(JSON.stringify({ id, method, params, sessionId }));
    });
  }
  const { targetId } = await call("Target.createTarget", {
    url: "about:blank",
  });
  const { sessionId } = await call("Target.attachToTarget", {
    targetId,
    flatten: true,
  });
  const cmd = (method, params = {}) => call(method, params, sessionId);
  await cmd("Page.enable");
  const results = [];
  for (const [name, width, height, scheme] of [
    ["desktop-light", 1440, 1200, "light"],
    ["desktop-dark", 1440, 1200, "dark"],
    ["mobile-light", 390, 844, "light"],
    ["mobile-dark", 390, 844, "dark"],
  ]) {
    await cmd("Emulation.setDeviceMetricsOverride", {
      width,
      height,
      deviceScaleFactor: 1,
      mobile: false,
    });
    await cmd("Emulation.setEmulatedMedia", {
      features: [
        { name: "prefers-color-scheme", value: scheme },
        { name: "prefers-reduced-motion", value: "reduce" },
      ],
    });
    const loaded = new Promise((resolve) => {
      const listener = ({ data }) => {
        const event = JSON.parse(data);
        if (
          event.method === "Page.loadEventFired" &&
          event.sessionId === sessionId
        ) {
          socket.removeEventListener("message", listener);
          resolve();
        }
      };
      socket.addEventListener("message", listener);
    });
    await cmd("Page.navigate", {
      url: `http://127.0.0.1:${server.address().port}/`,
    });
    await loaded;
    const readiness = await cmd("Runtime.evaluate", {
      expression: `new Promise(resolve => { const done = async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.decode().catch(() => {}))); resolve(true); }; if (document.readyState === 'complete') done(); else addEventListener('load', done, {once:true}); })`,
      awaitPromise: true,
    });
    if (readiness.exceptionDetails) throw new Error("Page did not load");
    const { result } = await cmd("Runtime.evaluate", {
      returnByValue: true,
      expression: `JSON.stringify({overflow:document.documentElement.scrollWidth>innerWidth,images:[...document.images].every(i=>i.complete&&i.naturalWidth>0),dark:matchMedia('(prefers-color-scheme:dark)').matches,reduced:matchMedia('(prefers-reduced-motion:reduce)').matches,title:document.title,smallTargets:[...document.querySelectorAll('a')].filter(a=>a.getBoundingClientRect().width>0&&!a.classList.contains('skip-link')).filter(a=>a.getBoundingClientRect().height<44).length})`,
    });
    const state = JSON.parse(result.value);
    if (
      !state.title.startsWith("yiyi") ||
      state.overflow ||
      !state.images ||
      state.dark !== (scheme === "dark") ||
      !state.reduced ||
      state.smallTargets
    )
      throw new Error(`${name}: ${JSON.stringify(state)}`);
    await cmd("Input.dispatchKeyEvent", {
      type: "keyDown",
      key: "Tab",
      code: "Tab",
      windowsVirtualKeyCode: 9,
    });
    await cmd("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: "Tab",
      code: "Tab",
      windowsVirtualKeyCode: 9,
    });
    const focus = await cmd("Runtime.evaluate", {
      expression: `document.activeElement.classList.contains('skip-link')`,
    });
    if (!focus.result.value)
      throw new Error(`${name}: keyboard skip-link focus failed`);
    const layout = await cmd("Page.getLayoutMetrics");
    const screenshot = await cmd("Page.captureScreenshot", {
      format: "png",
      captureBeyondViewport: true,
      clip: {
        x: 0,
        y: 0,
        width,
        height: layout.cssContentSize.height,
        scale: 1,
      },
    });
    await writeFile(
      resolve(output, `${name}.png`),
      Buffer.from(screenshot.data, "base64"),
    );
    results.push({ name, passed: true, ...state });
  }
  await writeFile(
    resolve(output, "checks.json"),
    JSON.stringify(results, null, 2),
  );
  console.log(
    `PASS: four Chrome layouts, all images, no overflow, 44px targets, keyboard focus, reduced motion. Artifacts: ${output}`,
  );
} finally {
  clearTimeout(watchdog);
  socket?.close();
  chrome.kill();
  server.close();
  // The profile is disposable; leave captures in the reported artifact directory.
  await new Promise((resolve) =>
    chrome.exitCode !== null ? resolve() : chrome.once("exit", resolve),
  );
  await rm(profile, { recursive: true, force: true });
}
