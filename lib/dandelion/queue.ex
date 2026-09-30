defmodule Dandelion.Queue do
  @moduledoc """
  The Oban setup of a dandelion app: what queues exist, the schedule, and how
  a job left by a dead node is given back.

      {Oban, Dandelion.Queue.config(otp_app: :my_app, repo: MyApp.Repo, crontab: MyApp.Cron.schedule())}

    * `default` and `ordered` queues, 10 jobs at once each, on every node.
      `ordered` is for `Dandelion.Queue.Ordered` workers.
    * `crontab`: `[{cron expression, worker}]`, run by one node only (Oban's
      leader), once per tick for the whole cluster.
    * A job left `executing` by a node that died is given back after
      `rescue_after` — five minutes by default. A job that genuinely runs
      longer may then run twice: keep jobs short, or raise it.
    * Finished jobs are kept a week.

  `config :my_app, Oban, …` overrides any of it (tests use `testing: :manual`).
  Options here: `:otp_app` and `:repo` (required), `:crontab` (default none).
  """

  @doc "The keyword list for `{Oban, …}`."
  @spec config(keyword()) :: keyword()
  def config(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    Keyword.merge(
      [
        repo: Keyword.fetch!(opts, :repo),
        queues: [default: 10, ordered: 10],
        cron: [crontab: Keyword.get(opts, :crontab, [])],
        lifeline: [rescue_after: {5, :minutes}],
        pruner: [max_age: {7, :days}]
      ],
      Application.get_env(otp_app, Oban, [])
    )
  end
end
