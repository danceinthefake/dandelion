defmodule Platform.Application do
  @moduledoc """
  What starts, in order — the map of the whole platform. ≈ `main.go`.

  Each child is a supervised process: if one crashes, the supervisor
  restarts it (see the phrasebook, "When it crashes").
  """
  use Application

  alias Platform.Web.Endpoint

  @impl true
  def start(_type, _args) do
    # Tracing: a span for each request (Bandit, then the Phoenix route), each
    # database query and each job. A job continues the trace of what queued it
    # (`:child`), on whichever node runs it. Where the spans go: config/runtime.exs.
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:platform, :database, :repo])
    OpentelemetryOban.setup(job: [span_relationship: :child])

    children =
      [
        # metrics
        Platform.Web.Telemetry,
        # ≈ Cloud SQL connection pool
        Platform.Database.Repo,
        # ≈ service discovery: nodes find each other through Postgres
        {Dandelion.Cluster, otp_app: :acme, repo: Platform.Database.Repo},
        # ≈ Redis pub/sub: live broadcast, fire-and-forget, reaches every node
        {Phoenix.PubSub, name: Platform.Broadcast},
        # ≈ Pusher presence: who is connected, across nodes
        Platform.Realtime.Presence,
        # ≈ Redis as a cache: in memory on each node, cleared across nodes
        {Dandelion.Cache, pubsub: Platform.Broadcast},
        # ≈ Redis INCR with an expiry: request limits, in memory on each node
        Dandelion.RateLimit,
        # ≈ a circuit breaker + timeout + retry for calls to other services
        Dandelion.Resilience,
        # ≈ Cloud Tasks + Cloud Scheduler: background jobs and cron
        {Oban, Platform.Queue.config()},
        # ≈ the web servers. Last, so it stops first: a node stops accepting requests
        # and finishes the ones in flight before the jobs and the database go.
        Endpoint
      ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Platform.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Runs when the node is told to stop (SIGTERM), before anything is shut down:
  # say so on /health, keep serving while the load balancer notices, and only
  # then let the supervision tree stop the endpoint, which drains what is in flight.
  @impl true
  def prep_stop(state) do
    Dandelion.Drain.start(Application.fetch_env!(:acme, :drain_delay))
    state
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
