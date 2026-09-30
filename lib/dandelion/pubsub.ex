defmodule Dandelion.PubSub do
  @moduledoc """
  Durable pub/sub: a topic, and the workers that each get every event.
  ≈ Google Pub/Sub topics with subscriptions, or Kafka consumer groups.

  `publish/3` adds one Oban job per subscriber, so each subscriber:

    * gets the event **at least once** — it is retried if it fails, and run
      again if its node dies, so it must be safe to run twice;
    * is retried **on its own** — a failing subscriber doesn't hold back the
      others;
    * runs on **any node**.

  Call it inside the `Repo.transact/1` that changes the data: the change and
  its event are saved together, or not at all. With an external broker that
  is the dual-write problem (saved, crashed before publishing, event lost).

  A subscriber is an Oban worker; its `perform/1` gets
  `%{"topic" => topic, "payload" => payload}` — the payload is JSON, so keys
  are strings.

  The topic → subscribers list belongs to your app. Keep it in one place, like
  a crontab, and publish through a small module of your own:

      defmodule MyApp.PubSub do
        def subscriptions, do: %{"order.created" => [MyApp.Workers.SendConfirmation]}

        def publish(topic, payload),
          do: Dandelion.PubSub.publish(subscriptions(), topic, payload)
      end

  Not this: a `Phoenix.PubSub` broadcast is for live views — fast, memory only,
  lost if nobody is listening. Order between events isn't kept; a subscriber
  that needs it uses `Dandelion.Queue.Ordered`.
  """

  @doc """
  Queues the event for every subscriber of `topic` in `subscriptions`
  (`%{topic => [worker]}`); returns their jobs. A topic that isn't in the map
  raises: it is a typo, not "no subscribers".
  """
  @spec publish(%{String.t() => [module()]}, String.t(), map()) :: [Oban.Job.t()]
  def publish(subscriptions, topic, payload) do
    args = %{"topic" => topic, "payload" => payload}

    workers =
      subscriptions[topic] ||
        raise ArgumentError, "no subscriptions for topic #{inspect(topic)}"

    workers
    |> Enum.map(& &1.new(args))
    |> Oban.insert_all()
  end
end
