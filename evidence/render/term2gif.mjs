// Replays a (timestamped) log as a terminal and records it as a GIF.
//
//   node render/term2gif.mjs IN.log OUT.gif "title"
//
// Lines look like "HH:MM:SS text" (as record.sh writes them) or plain text.
// The gaps between timestamps are kept but squeezed, so a 10 s wait is a
// visible pause and not a 10 s GIF. Needs Playwright (PLAYWRIGHT=path to its
// index.mjs, or `npm install` in evidence/) and ffmpeg.
import { readFileSync, mkdirSync, rmSync, readdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";

const [, , input, output, title = "terminal"] = process.argv;
const { chromium } = await import(process.env.PLAYWRIGHT ?? "playwright");

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
const secs = (t) => Number(t.slice(0, 2)) * 3600 + Number(t.slice(3, 5)) * 60 + Number(t.slice(6, 8));

const lines = readFileSync(input, "utf8")
  .split("\n")
  .filter((l) => l.trim() !== "" && !l.startsWith("#"))
  .map((raw) => {
    const m = raw.match(/^(\d\d:\d\d:\d\d) (.*)$/);
    return { t: m ? secs(m[1]) : null, text: m ? m[2] : raw };
  });

// delay before each line: real gap, squeezed
let prev = null;
const steps = lines.map((l) => {
  const gap = l.t !== null && prev !== null ? l.t - prev : 0;
  if (l.t !== null) prev = l.t;
  return { ...l, delay: Math.min(0.15 + Math.min(gap, 12) * 0.22, 2.6) };
});

const cls = (t) =>
  /^\s*ok\b/.test(t) ? "ok" : /^FAIL/.test(t) ? "fail" : /^[a-z][a-z ]*:$/.test(t.trim()) ? "head" : "";

const W = 960;
const H = Math.min(120 + steps.length * 22, 720);
const html = `<!doctype html><meta charset=utf-8><style>
body{margin:0;background:#0f1117;color:#d6dae3;font:15px/22px ui-monospace,Menlo,Consolas,monospace}
.bar{padding:8px 14px;background:#1b1f2a;color:#8b93a7;border-bottom:1px solid #2a3040}
pre{margin:0;padding:12px 14px;white-space:pre-wrap;word-break:break-word}
.ok{color:#6fdc8c}.fail{color:#ff6b6b;font-weight:bold}.head{color:#7aa2ff;font-weight:bold}
</style><div class=bar>${esc(title)}</div><pre id=t></pre>
<script>
const steps=${JSON.stringify(steps.map((s) => ({ d: s.delay, h: `<span class="${cls(s.text)}">${esc(s.text)}</span>` })))};
const t=document.getElementById("t");let i=0;
(function next(){ if(i>=steps.length){window.done=true;return}
  const s=steps[i++]; setTimeout(()=>{t.insertAdjacentHTML("beforeend",s.h+"\\n");window.scrollTo(0,document.body.scrollHeight);next()},s.d*1000)})();
</script>`;

const work = join(dirname(output), ".render");
rmSync(work, { recursive: true, force: true });
mkdirSync(work, { recursive: true });

const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width: W, height: H },
  recordVideo: { dir: work, size: { width: W, height: H } },
});
const page = await ctx.newPage();
await page.setContent(html);
await page.waitForFunction(() => window.done, null, { timeout: 300000 });
await page.waitForTimeout(2500); // hold the last frame
await ctx.close();
await browser.close();

const webm = readdirSync(work).find((f) => f.endsWith(".webm"));
execFileSync("ffmpeg", [
  "-y", "-loglevel", "error", "-i", join(work, webm),
  "-filter_complex",
  "fps=8,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=48[p];[b][p]paletteuse=dither=none",
  output,
]);
rmSync(work, { recursive: true, force: true });
console.log(`${output} written`);
