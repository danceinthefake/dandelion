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
    children =
      [
        # metrics
        Platform.Web.Telemetry,
        # ≈ Cloud SQL connection pool
        Platform.Database.Repo,
        # ≈ Redis pub/sub (on this node, for now)
        {Phoenix.PubSub, name: Platform.PubSub},
        # ≈ Cloud Tasks + Cloud Scheduler: background jobs and cron
        {Oban, Platform.Queue.config()},
        # ≈ the web servers
        Endpoint
      ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Platform.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
