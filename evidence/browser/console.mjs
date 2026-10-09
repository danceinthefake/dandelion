// Drives the console in a real browser against the 3-node cluster (nginx on :8080), through everything
// it can do: the account pages the emailed links open, searching as you type, the pages for staff,
// uploads, and a customer's narrower view. Prints a line per thing checked (a failed one stops it),
// takes a screenshot of each page, and records the whole run as a GIF.
//
//   node browser/console.mjs OUT_DIR
//
// The cluster must be up and seeded, with mailpit (record.sh does that). Needs Playwright and ffmpeg.
import { mkdirSync, rmSync, readdirSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const out = process.argv[2];
const { chromium } = await import(process.env.PLAYWRIGHT ?? "playwright");
const app = process.env.URL ?? "http://localhost:8080";
const mailpit = process.env.MAILPIT ?? "http://localhost:18025";
const size = { width: 1100, height: 780 };
const work = join(out, ".render");
rmSync(work, { recursive: true, force: true });
mkdirSync(work, { recursive: true });
mkdirSync(out, { recursive: true });

const tag = String(Date.now() % 1_000_000);
const PW = "correct horse battery";
const NEW_PW = "a brand new password";
const lines = [];
const log = (msg) => {
  lines.push(msg);
  console.log(`  ok  ${msg}`);
};
// `cond` is a function; it is tried again for a few seconds (the page answers asynchronously)
async function poll(cond, ms) {
  const end = Date.now() + ms;
  for (;;) {
    try {
      if (await cond()) return true;
    } catch {
      // not there yet
    }
    if (Date.now() > end) return false;
    await new Promise((r) => setTimeout(r, 200));
  }
}
async function check(cond, msg, ms = 7000) {
  if (!(await poll(cond, ms))) {
    console.error(`FAIL  ${msg}`);
    await page.screenshot({ path: join(out, "failure.png") }).catch(() => {});
    console.error((await page.locator("body").innerText().catch(() => "")).replace(/\n+/g, " | ").slice(0, 500));
    process.exitCode = 1;
    throw new Error(msg);
  }
  log(msg);
}

// start from "orders open", whatever an earlier run left
{
  const { token } = await fetch(`${app}/api/session`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email: "admin@example.com", password: "local-password-1" }) }).then((r) => r.json());
  await fetch(`${app}/api/flags/orders.enabled`, { method: "DELETE", headers: { authorization: `Bearer ${token}` } });
}

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: size, recordVideo: { dir: work, size } });
const page = await ctx.newPage();
const pause = (ms = 500) => page.waitForTimeout(ms);
const shot = (name) => page.screenshot({ path: join(out, `${name}.png`) });
const visible = (id) => page.getByTestId(id).waitFor({ state: "visible", timeout: 8000 }).then(() => true, () => false);
const text = (loc) => loc.innerText();

// mail the mail server holds for an address: [{ID, Subject}] newest first
async function mail(to, subject) {
  for (let i = 0; i < 40; i++) {
    const q = encodeURIComponent(`to:${to}${subject ? ` subject:${subject}` : ""}`);
    const res = await fetch(`${mailpit}/api/v1/search?query=${q}`).then((r) => r.json());
    if (res.messages?.length) return res.messages[0];
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error(`no email to ${to}`);
}
async function linkIn(to, subject) {
  const m = await mail(to, subject);
  const msg = await fetch(`${mailpit}/api/v1/message/${m.ID}`).then((r) => r.json());
  const link = msg.Text.match(/(https?:\/\/\S+\/#\/\S+)/)?.[1];
  if (!link) throw new Error(`no link in the email to ${to}`);
  return link;
}

async function signIn(email, password) {
  await page.getByTestId("email").fill(email);
  await page.getByTestId("password").fill(password);
  await page.getByTestId("sign-in").click();
}
const signOut = async () => {
  await page.getByTestId("sign-out").click();
  await page.getByTestId("sign-in").waitFor();
};

// ---------------------------------------------------------------- a new customer
console.log("a new customer:");
const alice = `alice-${tag}@example.com`;
await page.goto(`${app}/`);
await page.getByTestId("register-link").click();
await page.getByTestId("register").waitFor(); // (the sign-in page has an "email" field too, until the page changes)
await page.getByTestId("email").fill(alice);
await page.getByTestId("password").fill(PW);
await pause(300);
await shot("register");
await page.getByTestId("register").click();
await check(() => visible("unconfirmed"), "creating an account signs in, and says the address is not confirmed yet");
await shot("unconfirmed");

const confirmLink = await linkIn(alice, "Confirm");
await page.goto(confirmLink);
await check(() => visible("confirmed"), "the link in the email opens the console and confirms the address");
await page.goto(`${app}/`);
await page.getByTestId("me").waitFor();
await check(() => page.getByTestId("unconfirmed").count().then((n) => n === 0), "the warning is gone");
await check(() => 
  Promise.all(["nav-products", "nav-files"].map((t) => visible(t))).then((v) => v.every(Boolean)) &&
    page.getByTestId("nav-audit").count().then((n) => n === 0),
  "a customer sees Products and Files, and not the staff pages",
);
await page.goto(`${app}/#/audit`);
await check(() => visible("staff-only"), "the audit page, opened by hand, says it is for staff");
await signOut();

// ---------------------------------------------------------------- a forgotten password
console.log("a forgotten password:");
await page.getByTestId("forgot-link").click();
await page.getByTestId("ask").waitFor();
await page.getByTestId("email").fill(alice);
await page.getByTestId("ask").click();
await check(() => visible("sent"), "asking shows the same words for any address");
await shot("forgot");
const resetLink = await linkIn(alice, "Reset");
await page.goto(resetLink);
await page.getByTestId("new-password").fill("short");
await page.getByTestId("new-password-again").fill("short");
await page.getByTestId("reset").click();
await check(() => visible("reset-error"), "a password that is too short is refused, and the page says why");
await page.getByTestId("new-password").fill(NEW_PW);
await page.getByTestId("new-password-again").fill("something else entirely");
await page.getByTestId("reset").click();
await check(() => text(page.getByTestId("reset-error")).then((t) => /not the same/.test(t)), "two different passwords are refused before anything is sent");
await page.getByTestId("new-password").fill(NEW_PW);
await page.getByTestId("new-password-again").fill(NEW_PW);
await page.getByTestId("reset").click();
await check(() => visible("reset-done"), "a good password is accepted");
await shot("reset");
await page.goto(resetLink);
await page.reload(); // (the same address: a fresh page, as clicking the link again would give)
await page.getByTestId("new-password").fill("another good password");
await page.getByTestId("new-password-again").fill("another good password");
await page.getByTestId("reset").click();
await check(() => text(page.getByTestId("reset-error")).then((t) => /not valid/.test(t)), "the same link a second time is refused");
await page.goto(`${app}/`);
await signIn(alice, PW);
await check(() => text(page.getByTestId("sign-in-error")).then((t) => /invalid email or password/.test(t)), "the old password no longer signs in");
await signIn(alice, NEW_PW);
await check(() => visible("me"), "the new one does");
await signOut();

// ---------------------------------------------------------------- guessing
console.log("guessing:");
const bob = `bob-${tag}@example.com`;
await fetch(`${app}/api/users`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email: bob, password: PW }) });
for (let i = 1; i <= 5; i++) {
  await signIn(bob, `wrong password ${i}`);
  await page.getByTestId("sign-in-error").waitFor();
}
await signIn(bob, PW);
await check(() => 
  text(page.getByTestId("sign-in-error")).then((t) => /too many wrong passwords/.test(t) && /15 minutes/.test(t)),
  "five wrong passwords lock the address: even the right one is refused, and the page says for how long",
);
await shot("locked");

// ---------------------------------------------------------------- staff
console.log("staff:");
await page.goto(`${app}/`);
await signIn("admin@example.com", "local-password-1");
await page.getByTestId("node").waitFor();
await check(() => visible("nav-audit"), "the admin sees every page");

await page.getByTestId("order-email").fill(`ui-${tag}@example.com`);
await page.getByTestId("order-create").click();
await page.getByText(`ui-${tag}@example.com`).first().waitFor({ timeout: 8000 });
log("an order made in the form appears in the live list");
await shot("orders");

// products: type-ahead
await page.getByTestId("nav-products").click();
await page.getByTestId("search").fill("gre");
await page.getByTestId("results").waitFor();
await check(() => text(page.getByTestId("results")).then((t) => /Green tea/.test(t)), "typing “gre” finds “Green tea”, without pressing anything");
await page.getByTestId("search").fill("grean tea");
await check(() => visible("fuzzy"), "a typo is forgiven, and the page says the names are only close");
await page.getByTestId("search").fill("zzqqxx");
await page.getByTestId("results").waitFor({ state: "detached" }).catch(() => {});
await check(() => text(page.getByTestId("search-status")).then((t) => /nothing found/.test(t)), "nothing found says so");
// a burst of keystrokes: only the last answer shows
await page.getByTestId("search").fill("");
await page.getByTestId("search").pressSequentially("green", { delay: 25 });
await check(() => text(page.getByTestId("search-status")).then((t) => /found for “green”/.test(t)), "typing fast shows the answer for what was typed last");

const sku = `UI-${tag}`;
await page.getByTestId("new-sku").fill(sku);
await page.getByTestId("new-name").fill(`Hillside ${tag} <i>oolong</i>`);
await page.getByTestId("new-price").fill("18.50");
await page.getByTestId("new-description").fill(`Picked by hand on the hills <img src=x onerror="window.__xss = 1"> every morning`);
await page.getByTestId("new-submit").click();
await page.getByTestId("results").waitFor();
await check(() => text(page.getByTestId("results")).then((t) => t.includes(`Hillside ${tag}`)), "a product just added is found at once");
await page.getByTestId("search").fill("hills");
await page.getByTestId("snippet").first().waitFor();
await check(() => page.locator(".snippet mark").first().innerText().then((t) => /hills/i.test(t)), "a word in the description is found, and marked");
await check(() => page.evaluate(() => window.__xss === undefined), "the description's HTML was shown as text and did not run");
await page.getByTestId("search").fill(`${tag} oolong`);
await check(() => text(page.getByTestId("results")).then((t) => t.includes("<i>oolong</i>")), "a name with HTML in it shows as the characters typed…");
await check(() => page.locator('[data-testid="results"] i').count().then((n) => n === 0), "…not as italics: nothing the admin typed becomes markup");
await page.getByTestId("search").fill("hills");
await check(() => page.getByTestId("order-email").isHidden(), "the orders page is hidden while another page is open (and its live list stays joined)");
await shot("products");

await page.getByTestId("edit").first().click();
await page.getByTestId("edit-name").fill(`Hillside ${tag} jasmine`);
await page.getByRole("button", { name: "Save" }).click();
await page.getByTestId("search").fill(`${tag} jasmine`);
await check(() => text(page.getByTestId("results")).then((t) => t.includes("jasmine")), "a renamed product is found by its new name");
// (a busy service answers 503; the page says so, and a person would press the button again)
let removed = false;
for (let attempt = 1; attempt <= 3 && !removed; attempt++) {
  await page.getByTestId("remove").first().click();
  await page.getByRole("button", { name: "Remove" }).click();
  removed = await poll(async () => {
    const results = page.getByTestId("results");
    return (await results.count()) === 0 || !(await results.innerText()).includes(sku);
  }, 4000);
  if (!removed) await page.getByTestId("search").fill(`${tag} jasmine`);
}
await check(() => removed, "a removed product is gone from the next search");

// settings: the switch that pauses orders
await page.getByTestId("nav-settings").click();
await page.locator('[data-testid="orders-switch"]:not([disabled])').waitFor({ state: "attached" }); // (disabled until the settings have loaded)
await page.getByText("Accept new orders").click(); // (the label: the switch itself is a hidden input)
await check(() => text(page.getByTestId("orders-state")).then((t) => /refused/.test(t)), "the switch pauses new orders, and the page says what that means");
await shot("settings");
await page.goto(`${app}/#/`);
await page.getByTestId("order-email").fill(`paused-${tag}@example.com`);
await page.getByTestId("order-create").click();
await check(() => text(page.getByTestId("order-error")).then((t) => /paused/.test(t)), "while paused, the order form says the orders are paused");
await page.getByTestId("nav-settings").click();
await page.locator('[data-testid="orders-switch"]:not([disabled])').waitFor({ state: "attached" });
await page.getByText("Accept new orders").click();
await check(() => text(page.getByTestId("orders-state")).then((t) => /accepted/.test(t)), "and the switch opens them again");

// audit
await page.getByTestId("nav-audit").click();
await page.getByTestId("audit-table").waitFor();
await check(() => text(page.getByTestId("audit-table")).then((t) => /flag\.set/.test(t) && /product\.created/.test(t) && /user:\d+/.test(t)), "the audit log shows the switch and the product, and who did them");
await page.getByTestId("audit-action").selectOption("flag.");
await page.getByTestId("audit-apply").click();
await pause(800);
const actions = await page.locator('[data-testid="audit-table"] tbody tr td:nth-child(3)').allInnerTexts();
await check(() => Promise.resolve(actions.length > 0 && actions.every((a) => a.startsWith("flag."))), `filtered to settings: ${actions.length} entries, all flag.*`);
await shot("audit");

// webhooks
await page.getByTestId("nav-webhooks").click();
await page.getByTestId("hook-url").fill("http://hook-receiver/hook");
await page.getByTestId("hook-add").click();
await check(() => text(page.getByTestId("secret")).then((t) => t.startsWith("whsec_")), "an endpoint is added, and its signing secret shown");
await shot("webhooks");
await page.reload();
await page.getByTestId("hooks").waitFor();
await check(() => page.getByTestId("secret").count().then((n) => n === 0), "after a reload the secret is not shown again");
await page.getByTestId("hook-remove").last().click();
await page.getByRole("button", { name: "Remove" }).click();
await pause(800);

// files
await page.getByTestId("nav-files").click();
const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from(`hello from the console ${tag}`.padEnd(2_000_000, "x"))]);
await page.locator('[data-testid="files"], :text("No files yet")').first().waitFor(); // (the list has loaded)
const had = await page.getByTestId("file-download").count();
await page.locator('input[type="file"]').setInputFiles({ name: "holiday.png", mimeType: "image/png", buffer: png });
await page.getByTestId("file-upload").click();
await check(async () => (await page.getByTestId("file-download").count()) > had, "the upload finishes and the list has one more", 15000);
await check(() => text(page.getByTestId("files")).then((t) => /holiday\.png/.test(t) && /image\/png/.test(t)), "a 2 MB file is uploaded and listed with its type");
const [download] = await Promise.all([page.waitForEvent("download"), page.getByTestId("file-download").first().click()]); // (newest first)
const saved = readFileSync(await download.path());
await check(() => Promise.resolve(saved.equals(png)), "downloading gives back the very same bytes");
await page.locator('input[type="file"]').setInputFiles({ name: "program.png", mimeType: "image/png", buffer: Buffer.from([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0, 0, 0]) });
await page.getByTestId("file-upload").click();
await check(() => text(page.getByTestId("file-error")).then((t) => /only PNG, JPEG, PDF and plain text/.test(t)), "a program named .png is refused: the bytes decide, not the name");
await shot("files");
const listed = await page.getByTestId("file-remove").count();
await page.getByTestId("file-remove").first().click();
await check(async () => (await page.getByTestId("file-remove").count()) === listed - 1, "a file is removed");

// ---------------------------------------------------------------- narrow screens
console.log("a phone:");
await page.setViewportSize({ width: 390, height: 800 });
let overflowing = [];
for (const path of ["/", "/products", "/audit", "/settings", "/webhooks", "/files"]) {
  await page.goto(`${app}/#${path}`);
  await pause(900);
  const wide = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  if (wide) overflowing.push(path);
}
await shot("phone");
await check(() => Promise.resolve(overflowing.length === 0), `no page is wider than a phone's screen (${overflowing.length ? "wide: " + overflowing.join(", ") : "6 pages checked"})`);
await page.setViewportSize(size);

await ctx.close();
await browser.close();

const video = join(work, readdirSync(work).find((f) => f.endsWith(".webm")));
execFileSync("ffmpeg", [
  "-y", "-loglevel", "error", "-i", video,
  "-vf", "setpts=0.6*PTS,fps=6,scale=900:-1:flags=lanczos,split[x][y];[x]palettegen=max_colors=96[p];[y][p]paletteuse=dither=none",
  join(out, "console.gif"),
]);
rmSync(work, { recursive: true, force: true });
console.log("console proof passed");
