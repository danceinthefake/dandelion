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
        {Phoenix.PubSub, name: Platform.PubSub}
      ] ++
        jobs() ++
        [
          # ≈ the web servers
          Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Platform.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Background jobs, each a supervised process (see App.Shop.Workers.*).
  # ≈ the goroutines main.go starts before serving HTTP.
  defp jobs do
    expire = Application.get_env(:acme, App.Shop.Workers.ExpireUnpaidOrders, [])

    if Keyword.get(expire, :enabled, true),
      do: [{App.Shop.Workers.ExpireUnpaidOrders, expire}],
      else: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
