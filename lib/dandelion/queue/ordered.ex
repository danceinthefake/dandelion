defmodule Dandelion.Queue.Ordered do
  @moduledoc """
  A queue that keeps order **per key**. ≈ SQS FIFO message groups, Kafka
  partitions, Pub/Sub ordering keys.

  The events of one order run one after another, in the order they reached
  Postgres; events of other orders run in parallel, on any node.

      # where the event arrives, inside a Repo.transact/1
      Ordered.insert(MyWorker.new(%{...}), "order:42")

      # first thing in MyWorker.perform/1
      with :ok <- Ordered.turn(job), do: ...

    * **Order is arrival at Postgres**, not the nodes' clocks. `insert/2` takes
      a lock on the key until the transaction commits, so a job can't become
      visible, and run, before an earlier one of the same key.
    * **A failing job blocks its key** while it retries, like a Kafka
      partition. Once it is discarded (out of attempts) it stops blocking.
    * A node that dies mid-job leaves it `executing`, which blocks the key
      until Oban's lifeline gives the job back — set `rescue_after` short
      enough for you.
    * Needs the index from `Dandelion.Migration`, and the default `Oban`
      instance (the one started as `{Oban, …}`).
    * Use an ordered queue (`queue: :ordered`) for the worker. One fixed key
      makes a global queue: one job at a time for the whole cluster.
  """
  import Ecto.Query

  alias Dandelion.Trace

  @unfinished ~w(available scheduled executing retryable)

  @doc "Adds the job to the line for `key`. Call inside a transaction."
  @spec insert(Ecto.Changeset.t(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def insert(job_changeset, key) do
    Oban.Repo.query!(Oban.config(Oban), "SELECT pg_advisory_xact_lock(hashtext($1))", [key])

    meta = Ecto.Changeset.get_field(job_changeset, :meta, %{})

    job_changeset
    |> Ecto.Changeset.change(meta: Map.put(meta, "ordered_key", key))
    |> Trace.propagate()
    |> Oban.insert()
  end

  @doc "`:ok` when no earlier job of this key is unfinished, else `{:snooze, 1}`."
  @spec turn(Oban.Job.t()) :: :ok | {:snooze, pos_integer()}
  def turn(%Oban.Job{id: id, meta: %{"ordered_key" => key}}) do
    earlier =
      from(j in Oban.Job,
        where: fragment("?->>'ordered_key' = ?", j.meta, ^key),
        where: j.id < ^id and j.state in @unfinished
      )

    if Oban.Repo.exists?(Oban.config(Oban), earlier), do: {:snooze, 1}, else: :ok
  end
end
