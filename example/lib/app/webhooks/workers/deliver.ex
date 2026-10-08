defmodule App.Webhooks.Workers.Deliver do
  @moduledoc """
  Sends one event to one endpoint, and keeps trying until it is received.

  What can happen, and what we do:

    * **2xx** — done.
    * **5xx, 408, 429, a timeout, a connection error** — the receiver is having a
      bad time: try again later (Oban, with a growing wait: `backoff/1`).
    * **another 4xx** — the receiver understood and said no (410 Gone: it is
      deactivated): retrying would only repeat it, so the job is cancelled.
    * **the circuit is open** (`Dandelion.Resilience`: this node has seen the
      receiver fail several times in a row) — nothing is sent; the job waits 30 s
      without using up an attempt. A dead receiver is left alone, and costs us a
      timestamp, not a worker stuck on a timeout.

  Delivery is **at least once**: the same event can arrive twice (we sent it, the
  answer was lost). Every attempt carries the same `webhook-id`, so a receiver can
  tell. Jobs are unique per (endpoint, event) so the event is queued once.
  """
  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 10,
    unique: [period: :infinity, keys: [:endpoint_id, :event_id], states: Oban.Job.states()]

  require Logger

  alias App.Webhooks.Services.{Delivery, EndpointService}
  alias Dandelion.Resilience

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case EndpointService.get(args["endpoint_id"]) do
      {:ok, %{active: true} = endpoint} -> send_it(endpoint, args)
      _gone_or_off -> {:cancel, "endpoint #{args["endpoint_id"]} is gone or inactive"}
    end
  end

  defp send_it(endpoint, args) do
    event = Map.take(args, ["type", "created_at", "data"]) |> Map.put("id", args["event_id"])
    host = URI.parse(endpoint.url).host

    result =
      Resilience.call(
        {:webhook, host},
        fn -> Delivery.deliver(endpoint, args["event_id"], event) end,
        timeout: Delivery.timeout() + 2_000,
        failure_threshold: 5,
        reset_after: Application.get_env(:acme, :webhook_circuit_reset, 30_000)
      )

    handle(result, endpoint, args)
  end

  defp handle({:ok, _status}, _endpoint, _args), do: :ok

  defp handle({:error, :circuit_open}, endpoint, _args) do
    Logger.warning("webhook #{endpoint.id}: circuit open, waiting")
    {:snooze, 30}
  end

  defp handle({:error, {:status, 410}}, endpoint, _args) do
    EndpointService.deactivate(endpoint)
    {:cancel, "410 Gone: endpoint #{endpoint.id} deactivated"}
  end

  defp handle({:error, {:status, status}}, _endpoint, _args)
       when status in 400..499 and status not in [408, 429],
       do: {:cancel, "receiver answered #{status}"}

  defp handle({:error, reason}, endpoint, _args) do
    Logger.warning("webhook #{endpoint.id}: #{inspect(reason)}, will retry")
    {:error, inspect(reason)}
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    base = Application.get_env(:acme, :webhook_backoff_seconds, 30)
    wait = min(base * Integer.pow(2, attempt - 1), 3_600)
    # ±20 %: receivers that come back all at once should not be hit all at once
    round(wait * (0.8 + :rand.uniform() * 0.4))
  end
end
