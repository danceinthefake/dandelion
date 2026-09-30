defmodule Platform.Queue do
  @moduledoc """
  Background jobs. ≈ Cloud Tasks / RabbitMQ — but the jobs are rows in
  Postgres ([Oban](https://oban.hexdocs.pm)), next to your data. The queues,
  the lifeline and the pruner are set in `Dandelion.Queue.config/1` (the
  library); read its docs for what each does.

    * A job survives restarts and crashed nodes; any node runs it.
    * A job that fails is retried with backoff, up to its `max_attempts`.
    * Enqueueing inside a `Repo.transact/1` is atomic with the data change:
      both are saved, or neither.

  Workers live in their domain (`App.<Domain>.Workers.*`, `use Oban.Worker`);
  enqueue one with `Oban.insert(MyWorker.new(args))`. The schedule for
  recurring jobs is in `Platform.Cron`. One event for several workers:
  `Platform.PubSub`. Order per key: `Dandelion.Queue.Ordered`.
  """

  @doc "The Oban config; `config :acme, Oban` overrides it (tests use `testing: :manual`)."
  def config do
    Dandelion.Queue.config(
      otp_app: :acme,
      repo: Platform.Database.Repo,
      crontab: Platform.Cron.schedule()
    )
  end
end
