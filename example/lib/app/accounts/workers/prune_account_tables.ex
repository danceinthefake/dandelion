defmodule App.Accounts.Workers.PruneAccountTables do
  @moduledoc """
  Removes what the accounts domain no longer needs: one-time links that ended a week ago, and
  failed-login rows that are not locked and are a day old. Runs daily, from `Platform.Cron`.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias App.Accounts.Services.{LoginThrottle, TokenService}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    TokenService.prune()
    LoginThrottle.prune()
    :ok
  end
end
