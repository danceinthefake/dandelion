defmodule Shop.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        ShopWeb.Telemetry,
        Shop.Repo,
        {Phoenix.PubSub, name: Shop.PubSub}
      ] ++ jobs() ++ [ShopWeb.Endpoint]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Shop.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Background jobs, each a supervised process (see Shop.Jobs.*).
  # ≈ the goroutines main.go starts before serving HTTP.
  defp jobs do
    expire = Application.get_env(:shop, Shop.Jobs.ExpireUnpaidOrders, [])
    if Keyword.get(expire, :enabled, true), do: [{Shop.Jobs.ExpireUnpaidOrders, expire}], else: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ShopWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
