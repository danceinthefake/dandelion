// A screenshot of a web page, for the evidence: node shot.mjs URL OUT.png [WIDTH] [HEIGHT]
// Needs Playwright (PLAYWRIGHT=path to its index.mjs, as for term2gif.mjs).
const { chromium } = await import(process.env.PLAYWRIGHT ?? "playwright");

const [url, out, width = "1500", height = "2400"] = process.argv.slice(2);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: +width, height: +height }, deviceScaleFactor: 1 });
await page.goto(url, { waitUntil: "networkidle" });
// the panels draw after their queries come back
await page.waitForTimeout(8000);
await page.screenshot({ path: out, fullPage: false });
await browser.close();
console.log(`${out} written`);
