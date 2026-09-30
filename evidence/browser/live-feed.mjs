// Two browsers on the 3-node cluster (nginx on :8080), on two DIFFERENT
// nodes: an order made in one shows up in the other, in both directions, and
// presence counts both. Records both as one side-by-side GIF and a PNG.
//
//   node browser/live-feed.mjs OUT_DIR
//
// The cluster must be up (record.sh does that). Needs Playwright and ffmpeg.
import { mkdirSync, rmSync, readdirSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const out = process.argv[2];
const { chromium } = await import(process.env.PLAYWRIGHT ?? "playwright");
const url = process.env.URL ?? "http://localhost:8080/";
// wide enough for the desktop layout: the online count is in the sidebar
const size = { width: 900, height: 560 };
const work = join(out, ".render");

const browser = await chromium.launch();

// nginx spreads connections over the nodes; try until the two browsers have
// different ones (they do within a few tries).
async function pair() {
  rmSync(work, { recursive: true, force: true });
  mkdirSync(join(work, "a"), { recursive: true });
  mkdirSync(join(work, "b"), { recursive: true });
  const open = async (dir) => {
    const ctx = await browser.newContext({ viewport: size, recordVideo: { dir: join(work, dir), size } });
    const page = await ctx.newPage();
    await page.goto(url);
    await page.getByTestId("node").waitFor();
    return { ctx, page, node: (await page.getByTestId("node").innerText()).replace(/^.*connected to /, "") };
  };
  for (let i = 1; i <= 10; i++) {
    const a = await open("a");
    const b = await open("b");
    if (a.node !== b.node) return { a, b };
    await a.ctx.close();
    await b.ctx.close();
    rmSync(work, { recursive: true, force: true });
    mkdirSync(join(work, "a"), { recursive: true });
    mkdirSync(join(work, "b"), { recursive: true });
  }
  throw new Error("couldn't get two browsers onto two different nodes");
}

const { a, b } = await pair();
const log = [`browser A on ${a.node}`, `browser B on ${b.node}`];
const pause = (ms) => a.page.waitForTimeout(ms);

// presence: each sees both
for (const p of [a.page, b.page])
  await p.waitForFunction(() => /\b2\s*online now/.test(document.body.innerText));
log.push("presence: both pages show 2 online now");
await pause(1500);

async function make(from, to, email) {
  await from.page.getByLabel("Customer email").fill(email);
  await pause(600);
  await from.page.getByRole("button", { name: "New order" }).click();
  await to.page.getByText(email).first().waitFor({ timeout: 5000 });
  log.push(`order ${email}: made in ${from === a ? "A" : "B"} (${from.node}), shown in ${to === a ? "A" : "B"} (${to.node})`);
  await pause(1800);
}

const tag = Date.now() % 100000;
await make(a, b, `from-a-${tag}@example.com`);
await make(b, a, `from-b-${tag}@example.com`);
await a.page.screenshot({ path: join(out, "browser-a.png") });
await b.page.screenshot({ path: join(out, "browser-b.png") });

// closing B drops presence in A
await b.ctx.close();
await a.page.waitForFunction(() => /\b1\s*online now/.test(document.body.innerText), null, { timeout: 10000 });
log.push("presence: B closed, A shows 1 online now");
await pause(1500);
await a.ctx.close();
await browser.close();

const video = (d) => join(work, d, readdirSync(join(work, d)).find((f) => f.endsWith(".webm")));
execFileSync("ffmpeg", [
  "-y", "-loglevel", "error", "-i", video("a"), "-i", video("b"),
  "-filter_complex",
  "[0:v][1:v]hstack=inputs=2,fps=8,scale=1200:-1:flags=lanczos,split[x][y];[x]palettegen=max_colors=64[p];[y][p]paletteuse=dither=none",
  join(out, "live-feed.gif"),
]);
rmSync(work, { recursive: true, force: true });
writeFileSync(join(out, "browser.log"), log.join("\n") + "\n");
console.log(log.join("\n"));
