defmodule Platform.Web.Telemetry do
  @moduledoc """
  Metrics, in the Prometheus text format at `GET /metrics`
  (`Platform.Web.MetricsHandler`). ≈ the `promhttp` handler and the collectors
  you register in a Go service.

  The events come from Phoenix, Ecto, Oban, the VM and the dandelion library;
  `metrics/0` says which become metrics. Each node reports itself: Prometheus
  scrapes every node and adds them up (the cluster size, for one, is the same
  on all of them while the cluster is whole).

  Durations are histograms in seconds. To add a metric, add a line to
  `metrics/0` — and, for a number nobody emits as an event, a function to
  `periodic_measurements/0`.
  """
  use Supervisor
  import Telemetry.Metrics

  alias Platform.Database.Repo

  @reporter :platform_metrics
  # seconds
  @buckets [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # runs the periodic measurements below, every 10 s
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      {TelemetryMetricsPrometheus.Core, metrics: metrics(), name: @reporter}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "The metrics in the Prometheus text format (what `/metrics` returns)."
  def scrape, do: TelemetryMetricsPrometheus.Core.scrape(@reporter)

  def metrics do
    [
      # HTTP: how long requests take, and how many, by status (`_count` is the number)
      distribution("http.request.duration",
        description: "Requests, by status",
        event_name: [:phoenix, :endpoint, :stop],
        measurement: :duration,
        tags: [:status],
        tag_values: &%{status: &1.conn.status},
        unit: {:native, :second},
        reporter_options: [buckets: @buckets]
      ),
      distribution("http.handler.duration",
        description: "Time spent in a handler, by route",
        event_name: [:phoenix, :router_dispatch, :stop],
        measurement: :duration,
        tags: [:route],
        unit: {:native, :second},
        reporter_options: [buckets: @buckets]
      ),
      counter("http.handler.exceptions.total",
        description: "Handlers that crashed, by route",
        event_name: [:phoenix, :router_dispatch, :exception],
        measurement: :duration,
        tags: [:route]
      ),
      # WebSockets
      counter("phoenix.channel.joins.total",
        description: "Channel joins",
        event_name: [:phoenix, :channel_joined],
        measurement: :duration
      ),
      counter("phoenix.socket.connections.total",
        description: "Socket connections",
        event_name: [:phoenix, :socket_connected],
        measurement: :duration
      ),

      # Database: the pool is under pressure when queue time grows
      distribution("platform.database.repo.query.total_time",
        description: "Time of a database query, all in",
        unit: {:native, :second},
        reporter_options: [buckets: @buckets]
      ),
      distribution("platform.database.repo.query.queue_time",
        description: "Time spent waiting for a database connection",
        unit: {:native, :second},
        reporter_options: [buckets: @buckets]
      ),

      # Background jobs (Oban): how long they run, and how they ended
      distribution("oban.job.duration",
        description: "Jobs, by queue, worker and outcome",
        event_name: [:oban, :job, :stop],
        measurement: :duration,
        tags: [:queue, :worker, :state],
        unit: {:native, :second},
        reporter_options: [buckets: [0.01, 0.05, 0.1, 0.5, 1, 5, 30, 120]]
      ),
      counter("oban.job.exceptions.total",
        description: "Jobs that raised, by queue and worker",
        event_name: [:oban, :job, :exception],
        measurement: :duration,
        tags: [:queue, :worker]
      ),

      # dandelion's cache: hits and misses
      counter("dandelion.cache.fetches.total",
        description: "Cache fetches, hit or miss",
        event_name: [:dandelion, :cache, :fetch],
        measurement: :count,
        tags: [:result]
      ),

      # Calls to other services (Dandelion.Resilience): how they ended, and when a circuit
      # opens or closes — one circuit per thing called (`smtp:mailpit`, `webhook:example.com`)
      counter("dandelion.resilience.calls.total",
        description:
          "Calls to other services, by circuit and result (ok, error, timeout, circuit_open)",
        event_name: [:dandelion, :resilience, :call],
        measurement: :duration,
        tags: [:circuit, :result],
        tag_values: &circuit_tags/1
      ),
      counter("dandelion.resilience.circuit.changes.total",
        description: "Circuit state changes, by circuit and new state (open, half_open, closed)",
        event_name: [:dandelion, :resilience, :circuit],
        tags: [:circuit, :state],
        tag_values: &circuit_tags/1
      ),

      # Jobs waiting or running, by queue and state (from the table: the same on every node)
      last_value("platform.oban.queue.jobs",
        description: "Jobs by queue and state (available, scheduled, retryable, executing)",
        event_name: [:platform, :oban, :queue],
        measurement: :count,
        tags: [:queue, :state]
      ),

      # 1 while this node has been told to stop and is saying so on /health (Dandelion.Drain)
      last_value("platform.node.draining",
        description: "1 while this node is draining (told to stop), else 0",
        event_name: [:platform, :node, :draining],
        measurement: :value
      ),

      # The cluster: how many nodes this node is connected to, plus itself
      last_value("platform.cluster.nodes.count",
        description: "Nodes in the cluster as this node sees it (itself included)"
      ),

      # The VM
      last_value("vm.memory.total", unit: :byte, description: "Memory used by the VM"),
      last_value("vm.total_run_queue_lengths.total",
        description: "Processes waiting to run (scheduler load)"
      )
    ]
  end

  defp periodic_measurements do
    [{__MODULE__, :cluster_size, []}, {__MODULE__, :queue_depth, []}, {__MODULE__, :draining, []}]
  end

  # {:smtp, "mailpit"} → "smtp:mailpit"; a name that is not a pair is shown as it is
  defp circuit_tags(%{name: {kind, host}} = metadata),
    do: Map.put(metadata, :circuit, "#{kind}:#{host}")

  defp circuit_tags(%{name: name} = metadata), do: Map.put(metadata, :circuit, inspect(name))

  @doc false
  # Jobs that are not finished, by queue and state. A database that does not answer is
  # no reason to stop reporting everything else: the numbers just aren't updated.
  def queue_depth do
    sql = """
    SELECT queue, state, count(*) FROM oban_jobs
    WHERE state IN ('available', 'scheduled', 'retryable', 'executing') GROUP BY 1, 2
    """

    with {:ok, %{rows: rows}} <- Repo.query(sql, [], timeout: 2_000) do
      found = Map.new(rows, fn [queue, state, count] -> {{queue, state}, count} end)

      # every queue and state, zero when nothing is there: a line on a graph that is flat at
      # zero says "empty"; a missing line says nothing
      for queue <- queues(), state <- ~w(available scheduled retryable executing) do
        count = Map.get(found, {queue, state}, 0)

        :telemetry.execute([:platform, :oban, :queue], %{count: count}, %{
          queue: queue,
          state: state
        })
      end
    end

    :ok
  rescue
    # (no connection to check out, a stopped pool …)
    _ -> :ok
  end

  defp queues, do: Oban.config().queues |> Keyword.keys() |> Enum.map(&to_string/1)

  @doc false
  def draining do
    :telemetry.execute([:platform, :node, :draining], %{
      value: if(Dandelion.Drain.draining?(), do: 1, else: 0)
    })
  end

  @doc false
  def cluster_size do
    :telemetry.execute([:platform, :cluster, :nodes], %{count: length(Node.list()) + 1})
  end
end
