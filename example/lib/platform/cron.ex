defmodule Platform.Cron do
  @moduledoc """
  Recurring jobs: which worker runs when. ≈ Cloud Scheduler / a crontab.

  Standard cron syntax, in UTC. Oban runs this schedule on one node only —
  its leader, chosen through Postgres — so each entry runs once per tick for
  the whole cluster, however many nodes are up. If the leader dies, another
  node takes over.
  """

  @doc "The crontab: `{cron expression, worker}` pairs."
  def schedule do
    [
      # every minute: cancel orders unpaid for too long
      {"* * * * *", App.Shop.Workers.ExpireUnpaidOrders}
    ]
  end
end
