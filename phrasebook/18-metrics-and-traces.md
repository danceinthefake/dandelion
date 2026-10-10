# 18. Metrics and traces

**In Go**, a service usually has two extra pieces of wiring: `promhttp` for Prometheus metrics and `otel-go` for traces. Each thing that you want to see needs a wrapper: `otelhttp` around the router, `otelsql` around the database, and your own spans for the rest:

```go
http.Handle("/metrics", promhttp.Handler())
handler := otelhttp.NewHandler(router, "server")      // a span per request
db, _ := otelsql.Open("pgx", dsn)                     // a span per query
```

**In Elixir**, the libraries already emit [`:telemetry`](https://hexdocs.pm/telemetry) events: Phoenix for requests, Ecto for queries, and Oban for jobs. Metrics and traces are two readers of the same events. Nothing wraps your code.

## Metrics: `GET /metrics`

[`lib/platform/web/telemetry.ex`](../example/lib/platform/web/telemetry.ex) lists the metrics in one function. [`MetricsHandler`](../example/lib/platform/web/metrics_handler.ex) serves them in the Prometheus text format:

```elixir
distribution("http.request.duration",
  event_name: [:phoenix, :endpoint, :stop],
  measurement: :duration,
  tags: [:status],
  unit: {:native, :second}
)
```

| Go | Elixir |
|---|---|
| `prometheus.NewHistogramVec(…)` + `Register` | one `distribution(…)` line in `metrics/0` |
| `timer := prometheus.NewTimer(h); defer timer.ObserveDuration()` | nothing, because the event already carries the duration |
| a gauge you update from a goroutine | `last_value(…)` and a function in `periodic_measurements/0` (the cluster size is one gauge) |
| `promhttp.Handler()` | `GET /metrics`, where each node reports itself and Prometheus scrapes every node |

The example reports these metrics without extra work: requests by status, handler time by route, database query time, pool-queue time, Oban jobs by queue and worker and outcome, the hits and misses of the cache, the cluster size, and VM memory.

## Traces: one request, several nodes

```elixir
OpentelemetryBandit.setup()                           # the request
OpentelemetryPhoenix.setup(adapter: :bandit)          # the route
OpentelemetryEcto.setup([:platform, :database, :repo])  # each query
OpentelemetryOban.setup(job: [span_relationship: :child])  # each job
```

These four lines are in [`application.ex`](../example/lib/platform/application.ex). Your handlers have no wrappers.

In Go, you carry a trace from a request to the work that it queues when you put the trace context into the message yourself (a header or a field). The consumer reads it back. Here, the library does this. [`Dandelion.PubSub`](../lib/dandelion/pubsub.ex) and [`Dandelion.Queue.Ordered`](../lib/dandelion/queue/ordered.ex) store the current `traceparent` in the job. `opentelemetry_oban` starts the span of the job under it. An order made on one node therefore shows in Jaeger as one trace. The trace has the request on node A and its database queries. It also has the confirmation job and the statistics job, which run on node B.

To send spans to Jaeger, Tempo, or any collector, set `OTEL_EXPORTER_OTLP_ENDPOINT`. Without it, the service exports nothing.

**Why:** In Go, you add observability when you wrap each thing. On the BEAM, the libraries announce what they do, so adding a reader is the whole job. Jobs are rows, so the trace context can ride along in the row.
