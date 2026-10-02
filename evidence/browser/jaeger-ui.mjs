// A screenshot of one order's trace in Jaeger's UI: the request on one node and
// the order's jobs on another. Used by the tutorial.
//
//   node browser/jaeger-ui.mjs OUT_DIR
//
// The cluster must be up and seeded (record.sh live does that). Needs Playwright.
import { join } from "node:path";

const out = process.argv[2];
const { chromium } = await import(process.env.PLAYWRIGHT ?? "playwright");
const app = process.env.URL ?? "http://localhost:8080";
const jaeger = process.env.JAEGER ?? "http://localhost:16686";

const login = await fetch(`${app}/api/session`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ email: "admin@example.com", password: "local-password-1" }),
}).then((r) => r.json());

// An order, found again through Jaeger's own search (no made-up parent span, so
// the page shows a complete trace). Tried until a job runs on another node than
// the request (usually the first).
// warm-up: the first orders after boot are slower than the rest
for (let i = 0; i < 4; i++) {
  await fetch(`${app}/api/orders`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${login.token}` },
    body: JSON.stringify({ customer_email: "warmup@example.com", items: [{ sku: "TEA-01", quantity: 1 }] }),
  });
}
await new Promise((r) => setTimeout(r, 3000));

let traceId;
for (let i = 0; i < 12 && !traceId; i++) {
  const since = new Date(Date.now() - 1000).toISOString();
  await fetch(`${app}/api/orders`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${login.token}` },
    body: JSON.stringify({ customer_email: "sari@example.com", items: [{ sku: "TEA-01", quantity: 2 }] }),
  });
  const search =
    `${jaeger}/api/v3/traces?query.service_name=${process.env.SERVICE ?? "acme"}` +
    `&query.operation_name=${encodeURIComponent("POST /api/orders")}` +
    `&query.start_time_min=${since}&query.start_time_max=2999-01-01T00:00:00Z&query.num_traces=1`;
  for (let t = 0; t < 30 && !traceId; t++) {
    const found = await fetch(search).then((r) => r.json()).catch(() => ({}));
    const id = found.result?.resourceSpans?.[0]?.scopeSpans?.[0]?.spans?.[0]?.traceId;
    const res = id ? await fetch(`${jaeger}/api/traces/${id}`).then((r) => r.json()).catch(() => ({})) : {};
    const trace = res.data?.[0];
    if (trace) {
      const nodes = new Set(
        trace.spans.map((x) => trace.processes[x.processID].tags.find((y) => y.key === "service.instance.id")?.value),
      );
      const jobs = trace.spans.filter((x) => x.operationName.startsWith("process")).length;
      // not a cold start: the first requests after boot can be slow, and a
      // screenshot of those would suggest the app is
      const root = trace.spans.find((x) => x.operationName.startsWith("POST"));
      if (jobs >= 2 && nodes.size >= 2 && root && root.duration < 500_000) traceId = id;
      if (jobs >= 2) break;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
}
if (!traceId) throw new Error("no warm trace spanning two nodes after 12 orders");

const browser = await chromium.launch();
const page = await (await browser.newContext({ viewport: { width: 1280, height: 760 } })).newPage();
await page.goto(`${jaeger}/trace/${traceId}`);
await page.getByText("POST /api/orders").first().waitFor({ timeout: 20000 });
await page.waitForTimeout(1500);
await page.screenshot({ path: join(out, "jaeger-ui.png") });
await browser.close();
console.log(`trace ${traceId}`);
