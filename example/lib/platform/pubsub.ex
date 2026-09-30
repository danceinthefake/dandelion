defmodule Platform.PubSub do
  @moduledoc """
  Durable pub/sub: a topic, and the workers that each get every event.
  ≈ Google Pub/Sub topics with subscriptions, or Kafka consumer groups.

  `publish/2` (the mechanism is `Dandelion.PubSub`, in the library) adds one
  Oban job per subscriber, so each subscriber:

    * gets the event **at least once** — it is retried if it fails, and run
      again if its node dies, so it must be safe to run twice;
    * is retried **on its own** — a failing subscriber doesn't hold back the
      others;
    * runs on **any node**.

  Call it inside the `Repo.transact/1` that changes the data: the change and
  its event are saved together, or not at all. With an external broker that
  is the dual-write problem (saved, crashed before publishing, event lost).

  A subscriber is an Oban worker in its domain (`App.<Domain>.Workers.*`);
  its `perform/1` gets `%{"topic" => topic, "payload" => payload}` — the
  payload is JSON, so keys are strings.

  Not this: `Platform.Broadcast` is for live views — fast, memory only, lost
  if nobody is listening. Order between events isn't kept; a subscriber that
  needs it uses `Dandelion.Queue.Ordered`.
  """

  alias App.Shop.Workers.{SendOrderConfirmation, UpdateCustomerStats}

  @doc "Topic → subscribers. One place, like the crontab in `Platform.Cron`."
  def subscriptions do
    %{
      "order.created" => [SendOrderConfirmation, UpdateCustomerStats]
    }
  end

  @doc "Queues the event for every subscriber of `topic`; returns their jobs."
  @spec publish(String.t(), map()) :: [Oban.Job.t()]
  def publish(topic, payload), do: Dandelion.PubSub.publish(subscriptions(), topic, payload)
end
