defmodule Platform.Queue do
  @moduledoc """
  Background jobs. ≈ Cloud Tasks / RabbitMQ — but the jobs are rows in
  Postgres ([Oban](https://oban.hexdocs.pm)), next to your data.

    * A job survives restarts and crashed nodes; any node runs it.
    * A job that fails is retried with backoff, up to its `max_attempts`.
    * Enqueueing inside a `Repo.transact/1` is atomic with the data change:
      both are saved, or neither.

  Workers live in their domain (`App.<Domain>.Workers.*`, `use Oban.Worker`);
  enqueue one with `Oban.insert(MyWorker.new(args))`. The schedule for
  recurring jobs is in `Platform.Cron`.
  """

  @doc "The Oban config; `config :acme, Oban` overrides it (tests use `testing: :manual`)."
  def config do
    Keyword.merge(
      [
        repo: Platform.Database.Repo,
        # queue name: how many of its jobs run at once, on each node
        queues: [default: 10],
        cron: [crontab: Platform.Cron.schedule()],
        # A job left `executing` by a node that died is run again after this.
        # ponytail: a job that genuinely runs longer than 5 minutes may run
        # twice — keep jobs short, or raise this.
        lifeline: [rescue_after: {5, :minutes}],
        # finished jobs are kept a week, for looking back
        pruner: [max_age: {7, :days}]
      ],
      Application.get_env(:acme, Oban, [])
    )
  end
end
