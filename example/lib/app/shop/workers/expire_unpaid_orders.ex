defmodule App.Shop.Workers.ExpireUnpaidOrders do
  @moduledoc """
  Cancels orders that stayed unpaid longer than `:max_age_seconds`
  (`UNPAID_ORDER_MAX_AGE_SECONDS`, default 3600). Runs every minute, from
  `Platform.Cron`.

  ≈ in Go, the handler Cloud Scheduler calls — or a ticker goroutine, except
  a ticker runs on every instance. This runs once per minute for the whole
  cluster, and a failed run is retried.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias App.Shop.Services.OrderService

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    max_age = Application.fetch_env!(:acme, __MODULE__)[:max_age_seconds]
    count = OrderService.expire_unpaid(max_age)

    if count > 0, do: Logger.info("cancelled #{count} unpaid order(s) older than #{max_age}s")

    :ok
  end
end
