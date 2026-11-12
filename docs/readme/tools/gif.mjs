// Turns a reel (see reel.rb in this folder) into a GIF or one PNG.
//   node gif.mjs reel.json out.(gif|png) WIDTH HEIGHT [fps=20] [still frame]
// Needs Google Chrome and ffmpeg. COLORS and DITHER tune the GIF palette.
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const [reelPath, out, W, H, fpsOutArg, still] = process.argv.slice(2);
const width = +W, height = +H, fpsOut = +(fpsOutArg || 20);
const reel = JSON.parse(fs.readFileSync(reelPath, "utf8"));
const work = fs.mkdtempSync(path.join(path.dirname(path.resolve(reelPath)), "gif-"));
const v = reel.view, bg = reel.background || "white";
fs.writeFileSync(path.join(work, "page.html"), `<!doctype html><meta charset=utf-8>
<style>html,body{margin:0;background:${bg};overflow:hidden}svg{position:fixed;left:0;top:0;width:${width}px;height:${height}px;display:block}</style>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="${v.join(" ")}" preserveAspectRatio="xMidYMid ${process.env.SLICE ? "slice" : "meet"}" stroke-linejoin="round" stroke-linecap="round">
<rect x="${v[0] - v[2] * 5}" y="${v[1] - v[3] * 5}" width="${v[2] * 11}" height="${v[3] * 11}" fill="${bg}"/><g id="c"></g></svg>
<script>const F=${JSON.stringify(reel.frames).replace(/</g, "\\u003c")};const c=document.getElementById("c");window.setFrame=(n)=>{c.innerHTML=F[n];return n};window.READY=F.length;</script>`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const port = 9500 + Math.floor(Math.random() * 400);
const chrome = spawn(CHROME, ["--headless=new", "--hide-scrollbars", "--no-first-run", "--force-color-profile=srgb", "--allow-file-access-from-files",
  `--remote-debugging-port=${port}`, `--user-data-dir=${path.join(work, "profile")}`, `--window-size=${width},${height}`, "about:blank"], { stdio: "ignore" });
let ws;
const cleanup = () => { try { ws && ws.close(); } catch {} try { chrome.kill("SIGKILL"); } catch {} try { fs.rmSync(work, { recursive: true, force: true }); } catch {} };
process.on("exit", cleanup);
let target;
for (let i = 0; i < 100 && !target; i++) { try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find((t) => t.type === "page"); } catch {} if (!target) await sleep(150); }
if (!target) { console.error("Chrome did not start"); process.exit(1); }
ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let id = 0; const waiting = {};
ws.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (m.id && waiting[m.id]) { waiting[m.id](m); delete waiting[m.id]; } });
const send = (method, params = {}) => new Promise((resolve, reject) => { const i = ++id; waiting[i] = (r) => r.error ? reject(new Error(method + ": " + r.error.message)) : resolve(r); ws.send(JSON.stringify({ id: i, method, params })); });
const evaluate = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })).result?.result?.value;
await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false });
const loaded = new Promise((r) => { const h = (e) => { if (JSON.parse(e.data).method === "Page.loadEventFired") { ws.removeEventListener("message", h); r(); } }; ws.addEventListener("message", h); });
await send("Page.navigate", { url: "file://" + path.join(work, "page.html") });
await loaded;
const total = await evaluate("window.READY");
async function grab(n) {
  await evaluate(`setFrame(${n})`);
  await evaluate("new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))");
  const res = await send("Page.captureScreenshot", { format: "png", clip: { x: 0, y: 0, width, height, scale: 1 } });
  return Buffer.from(res.result.data, "base64");
}
if (out.endsWith(".png")) { fs.writeFileSync(out, await grab(+(still || 0) % total)); process.exit(0); }
const seconds = total / reel.fps, count = Math.max(1, Math.round(seconds * fpsOut));
const colors = process.env.COLORS || 128, dither = process.env.DITHER || "bayer:bayer_scale=4";
const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(count / seconds), "-c:v", "png", "-i", "-",
  "-filter_complex", `split[a][b];[a]palettegen=max_colors=${colors}:stats_mode=full[p];[b][p]paletteuse=dither=${dither}:diff_mode=rectangle`, "-loop", "0", out], { stdio: ["pipe", "inherit", "inherit"] });
for (let i = 0; i < count; i++) { const png = await grab(Math.floor(i * total / count)); if (!ff.stdin.write(png)) await new Promise((r) => ff.stdin.once("drain", r)); }
ff.stdin.end();
await new Promise((r) => ff.on("close", r));
console.error(`${out}: ${count} frames, ${(fs.statSync(out).size / 1000).toFixed(0)} KB`);
process.exit(0);
