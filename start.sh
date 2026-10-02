#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
/usr/bin/time -p pwd
/usr/bin/time -p bash -c 'PORT="${PORT:-3000}"; echo "PORT=$PORT"'
PROJECT_ROOT="$(pwd)"
/usr/bin/time -p bash -c 'echo "PROJECT_ROOT=$(pwd)"'
DIST_DIR="$PROJECT_ROOT/dist"
/usr/bin/time -p test -f "$DIST_DIR/index.html"
/usr/bin/time -p node --input-type=module -e '
import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { resolve } from "node:path";
const project = resolve(process.env.PROJECT_DIR || process.cwd());
const directory = resolve(project, "dist");
if (!existsSync(directory + "/index.html")) { console.error("Static deployment output must contain index.html."); process.exit(1); }
const webDir = process.env.OPENCODE_WEB_DIR || "/home/runner/work/_temp/omgithub-web";
mkdirSync(webDir, { recursive: true });
writeFileSync(webDir + "/deployment-output.json", JSON.stringify({ project, directory }));
console.log("deployment-output.json:", JSON.stringify({ project, directory }));
'
/usr/bin/time -p node --version
/usr/bin/time -p node --input-type=module -e '
import { createServer } from "node:http";
import { readFileSync, statSync, existsSync } from "node:fs";
import { resolve, join, extname } from "node:path";
const root = resolve(process.env.PROJECT_DIR || process.cwd(), "dist");
const port = Number(process.env.PORT || 3000);
const mime = { ".html":"text/html; charset=utf-8", ".js":"application/javascript; charset=utf-8", ".css":"text/css; charset=utf-8", ".json":"application/json", ".svg":"image/svg+xml", ".png":"image/png", ".jpg":"image/jpeg", ".webp":"image/webp", ".wasm":"application/wasm", ".ico":"image/x-icon", ".txt":"text/plain; charset=utf-8" };
const server = createServer((req, res) => {
  try {
    const url = new URL(req.url, "http://localhost");
    let p = decodeURIComponent(url.pathname);
    let file = resolve(root, "." + p);
    if (file !== root && !file.startsWith(root + "/")) { res.writeHead(404); res.end("Not found"); return; }
    try { if (statSync(file).isDirectory()) file = join(file, "index.html"); } catch { file = join(root, "index.html"); }
    if (!existsSync(file)) file = join(root, "index.html");
    res.setHeader("Content-Type", mime[extname(file).toLowerCase()] || "application/octet-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.end(readFileSync(file));
  } catch (e) { res.writeHead(500); res.end("Server error"); }
});
server.listen(port, "0.0.0.0", () => console.log("Serving " + root + " on port " + port));
'
