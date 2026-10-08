defmodule App.Webhooks.Workers.FanOut do
  @moduledoc """
  Subscriber of the topics a receiver can ask for (`Platform.PubSub`): turns one
  event into one delivery job per interested endpoint.

  A job per endpoint, so a receiver that is down is retried on its own and holds
  nobody back. The delivery jobs are unique per (endpoint, event): this worker is
  at-least-once like every subscriber, and running twice must not send twice.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias App.Webhooks.Services.EndpointService
  alias App.Webhooks.Workers.Deliver

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"topic" => topic, "payload" => payload}}) do
    event_id = "evt_" <> String.replace(topic, ".", "_") <> "_" <> to_string(payload["order_id"])

    # one by one: `Oban.insert_all/1` does not apply a worker's `unique`
    for endpoint <- EndpointService.subscribers(topic) do
      %{
        "endpoint_id" => endpoint.id,
        "event_id" => event_id,
        "type" => topic,
        "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "data" => payload
      }
      |> Deliver.new()
      |> Oban.insert!()
    end

    :ok
  end
end
