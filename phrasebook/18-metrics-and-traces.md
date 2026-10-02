# 18. Metrics and traces

**In Go** — a service usually has two extra pieces of wiring: `promhttp` for
Prometheus metrics and `otel-go` for traces, with a wrapper for each thing you
want to see (`otelhttp` around the router, `otelsql` around the database, and
your own spans for the rest):

```go
http.Handle("/metrics", promhttp.Handler())
handler := otelhttp.NewHandler(router, "server")      // a span per request
db, _ := otelsql.Open("pgx", dsn)                     // a span per query
```

**In Elixir** — the libraries already emit [`:telemetry`](https://hexdocs.pm/telemetry)
events (Phoenix for requests, Ecto for queries, Oban for jobs). Metrics and
traces are two readers of the same events; nothing wraps your code.

## Metrics: `GET /metrics`

[`lib/platform/web/telemetry.ex`](../example/lib/platform/web/telemetry.ex) lists
the metrics in one function, and
[`MetricsHandler`](../example/lib/platform/web/metrics_handler.ex) serves them in
the Prometheus text format:

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
| `timer := prometheus.NewTimer(h); defer timer.ObserveDuration()` | none: the event already carries the duration |
| a gauge you update from a goroutine | `last_value(…)` and a function in `periodic_measurements/0` (the cluster size is one) |
| `promhttp.Handler()` | `GET /metrics`; each node reports itself and Prometheus scrapes every node |

Reported out of the box: requests by status, handler time by route, database
query and pool-queue time, Oban jobs by queue / worker / outcome, the cache's
hits and misses, the cluster size, VM memory.

## Traces: one request, several nodes

```elixir
OpentelemetryBandit.setup()                           # the request
OpentelemetryPhoenix.setup(adapter: :bandit)          # the route
OpentelemetryEcto.setup([:platform, :database, :repo])  # each query
OpentelemetryOban.setup(job: [span_relationship: :child])  # each job
```

([`application.ex`](../example/lib/platform/application.ex).) Four lines, no
wrappers in your handlers.

In Go, carrying a trace from a request to the work it queues means putting the
trace context into the message yourself (a header, a field) and reading it back
in the consumer. Here the library does it:
[`Dandelion.PubSub`](../lib/dandelion/pubsub.ex) and
[`Dandelion.Queue.Ordered`](../lib/dandelion/queue/ordered.ex) store the current
`traceparent` in the job, and `opentelemetry_oban` starts the job's span under
it. An order made on one node therefore shows up in Jaeger as **one trace**:
the request on node A, its database queries, and the confirmation and stats jobs
running on node B.

Set `OTEL_EXPORTER_OTLP_ENDPOINT` to send spans to Jaeger, Tempo or any
collector; without it nothing is exported.

**Why:** in Go you add observability by wrapping each thing. On the BEAM the
libraries announce what they do, so adding a reader is the whole job — and
because jobs are rows, the trace context can ride along in the row.
