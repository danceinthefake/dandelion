defmodule App.Shop.Workers.ProcessPaymentEvent do
  @moduledoc """
  Applies one payment event from the provider to its order, on the ordered
  queue (`Platform.Queue.Ordered`): the events of one order run in the order
  they arrived, events of other orders in parallel.

    * `payment.succeeded` → the order becomes `paid`
    * `payment.refunded`  → the order becomes `refunded`

  Providers send the same event more than once, so the job is unique on the
  provider's `event_id`: the second one isn't queued. An event that doesn't
  fit the order's state (a payment for a cancelled order) is logged and
  dropped — retrying won't change that.
  """
  use Oban.Worker,
    queue: :ordered,
    max_attempts: 10,
    unique: [period: :infinity, keys: [:event_id]]

  require Logger

  alias App.Shop.Services.OrderService
  alias Platform.Queue.Ordered

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    with :ok <- Ordered.turn(job) do
      apply_event(args)
    end
  end

  defp apply_event(%{"type" => type, "order_id" => id, "event_id" => event_id}) do
    result =
      case type do
        "payment.succeeded" -> OrderService.mark_paid(id)
        "payment.refunded" -> OrderService.mark_refunded(id)
      end

    case result do
      {:ok, _order} ->
        :ok

      {:error, :not_found} ->
        {:cancel, "order #{id} not found"}

      {:error, {:conflict, message}} ->
        Logger.warning("payment event #{event_id} (#{type}) dropped: order #{id}: #{message}")
        :ok
    end
  end
end
