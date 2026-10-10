# 23 — A dashboard, checked against what it is for

Claim: The dashboard (`deploy/grafana/dashboards/dandelion.json`, which Grafana loads from a file) shows what happens, and every number on it is real.

1. The pieces work. Prometheus reads `/metrics` from all three nodes. Grafana has the dashboard (25 panels, provisioned read-only from the file) and reaches Prometheus.
2. The proof makes events happen. Each event has a panel:
   - 30 orders, searches, and unknown products (traffic and 404 answers).
   - A client over its rate limit (21 requests get 429).
   - Orders that a flag pauses (6 get 503).
   - A stopped mail server (8 mail jobs wait, and a circuit opens and is counted).
   - A node that gets the stop signal (the dashboard shows it draining).
3. Every query of the dashboard runs without error (30 queries). The 16 panels that show those events have data. They show requests by status, latency, requests for each node, the slowest routes, calls to other services by circuit, circuit changes, jobs that wait by queue, jobs and their time, the database wait, cache fetches, memory, scheduler load, and draining.

![the dashboard after the proof](dashboard.png)

[`render/shot.mjs`](../render/shot.mjs) takes the screenshot right after the proof, from the kiosk view of Grafana, for the last 3 minutes.

Code: the dashboard JSON, `prometheus.yml`, and the Grafana provisioning files in `example/deploy/`. The metrics are in `Platform.Web.Telemetry`. These metrics are new: calls and circuit changes by circuit, queue depth by queue and state, and draining. See DESIGN.md §10.21.

Negative controls ([`badpanel.log`](../controls/badpanel.log), [`nocircuitmetric.log`](../controls/nocircuitmetric.log)): A typo in the metric name of a panel runs and returns nothing. The proof stops at "the panels … have data". A circuit that opens but is not counted stops the proof at "the mail server stopped", because the dashboard could not have said so.

Found by running it:
- Prometheus got a refusal at `/metrics`. The production `force_ssl` redirected its plain-http scrape to https. `/metrics` is now excluded in the same way as `/health`.
- The queue-depth panel was empty when idle. A metric that the service makes only from existing rows has no series for an empty queue. The service now reports every queue and state, with zero when empty.
- The "draining" panel never showed a drain. A gauge that a poll sets every 10 s cannot see a drain of 5 s. The service now sets it when the drain starts.

Not shown:
- Alerting.
- A long run. The screenshot shows a minute of events on a fresh cluster.
- That the thresholds are right for any real service.

See [LIMITS.md](../LIMITS.md).

To run it again, run `evidence/record.sh dashboard`. This takes about 2 minutes and needs Playwright for the screenshot. To run the controls, run `ONLY=badpanel evidence/record.sh controls` and `ONLY=nocircuitmetric …`.
