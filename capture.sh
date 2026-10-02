#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
/usr/bin/time -p pwd
/usr/bin/time -p bash -c 'echo "CAPTURE_URL=${CAPTURE_URL:-<unset>}"; echo "CAPTURE_DIR=${CAPTURE_DIR:-<unset>}"'
test -n "${CAPTURE_URL:-}" || { echo "CAPTURE_URL is required" >&2; exit 1; }
test -n "${CAPTURE_DIR:-}" || { echo "CAPTURE_DIR is required" >&2; exit 1; }
/usr/bin/time -p mkdir -p "$CAPTURE_DIR"
/usr/bin/time -p bash -c 'echo "capturing $CAPTURE_URL -> $CAPTURE_DIR"'
/usr/bin/time -p node --input-type=module -e '
import { createRequire } from "node:module";
import { readFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
const runtime = join(process.env.HOME || "/home/runner", ".local/share/omgithub-playwright");
const require = createRequire(join(runtime, "package.json"));
const { chromium } = require("playwright");
const config = JSON.parse(readFileSync(join(runtime, process.platform === "darwin" ? "metal.json" : "linux.json"), "utf8"));
if (process.platform === "linux") {
  try { process.env.DISPLAY ||= ":" + readFileSync(join(runtime, "display"), "utf8").trim(); } catch {}
}
const url = process.env.CAPTURE_URL, output = process.env.CAPTURE_DIR;
if (!url || !output) { console.error("Set CAPTURE_URL and CAPTURE_DIR."); process.exit(1); }
mkdirSync(output, { recursive: true });
const TRANSIENT = new Set([408, 429, 500, 502, 503, 504]);
const transient = (err) => { throw Object.assign(err instanceof Error ? err : new Error(String(err)), { exitCode: 75 }); };
let browser;
try {
  browser = await chromium.launch({ ...config.browser.launchOptions, timeout: 30000 }).catch(transient);
  for (const [name, width, height] of [["desktop", 1440, 900], ["mobile", 390, 844]]) {
    const page = await browser.newPage({ viewport: { width, height } }).catch(transient);
    page.setDefaultTimeout(30000);
    page.on("pageerror", (e) => console.error("pageerror:", e.message));
    const response = await page.goto(url, { waitUntil: "load", timeout: 45000 }).catch(transient);
    if (!response?.ok()) {
      const st = response?.status();
      throw Object.assign(new Error("HTTP " + st + " loading preview"), { exitCode: !response || TRANSIENT.has(st) ? 75 : 1 });
    }
    await page.locator(process.env.CAPTURE_READY_SELECTOR || "body").waitFor({ state: "visible", timeout: 30000 }).catch(transient);
    try { await page.waitForFunction(() => document.fonts.status === "loaded", null, { timeout: 15000 }); } catch {}
    await page.waitForTimeout(1500);
    const bodyText = await page.evaluate(() => (document.body?.innerText || "").trim().length).catch(() => 0);
    if (!bodyText || bodyText < 20) throw Object.assign(new Error("Rendered content empty (chars=" + bodyText + ")"), { exitCode: 1 });
    await page.screenshot({ path: join(output, "final-" + name + ".png"), timeout: 30000 }).catch((error) => {
      if (error?.name === "TimeoutError" || !browser.isConnected()) transient(error);
      throw error;
    });
    console.log("captured final-" + name + ".png (chars=" + bodyText + ")");
    await page.close();
  }
} catch (error) {
  console.error(error);
  process.exitCode = error?.exitCode || 1;
} finally {
  await browser?.close().catch((error) => { console.error(error); process.exitCode ||= 75; });
}
'
status=$?
/usr/bin/time -p bash -c 'echo "capture exit=$1"; ls -l "$2"' _ "$status" "$CAPTURE_DIR"
/usr/bin/time -p test -f "$CAPTURE_DIR/final-desktop.png"
/usr/bin/time -p test -f "$CAPTURE_DIR/final-mobile.png"
exit "$status"
