defmodule App.Shop.Services.PaymentService do
  @moduledoc """
  Takes payment events from the provider (Midtrans, Xendit, Stripe …).
  ≈ `service/payments.go`.

  It only checks the event and queues it; the work happens in
  `App.Shop.Workers.ProcessPaymentEvent`, so the webhook answers fast and the
  provider doesn't time out and resend.
  """
  alias App.Shop.Workers.ProcessPaymentEvent
  alias Dandelion.Queue.Ordered
  alias Platform.Database.Repo

  @types ~w(payment.succeeded payment.refunded)
  @max_order_id 9_223_372_036_854_775_807

  @doc """
  Queues `%{"event_id" => "evt_1", "type" => "payment.succeeded", "order_id" => 42}`
  on the line for `order:42`. The same `event_id` twice is queued once.
  """
  @spec receive_event(map()) :: :ok | {:error, {:invalid, String.t()}}
  def receive_event(params) do
    with {:ok, args} <- validate(params),
         {:ok, _job} <-
           Repo.transact(fn ->
             args |> ProcessPaymentEvent.new() |> Ordered.insert("order:#{args["order_id"]}")
           end) do
      :ok
    end
  end

  defp validate(%{"event_id" => event_id, "type" => type, "order_id" => order_id})
       when is_binary(event_id) and byte_size(event_id) in 1..128 and type in @types and
              is_integer(order_id) and order_id in 1..@max_order_id//1 do
    {:ok, %{"event_id" => event_id, "type" => type, "order_id" => order_id}}
  end

  defp validate(_params) do
    {:error,
     {:invalid,
      "need event_id (text), order_id (whole number) and type (one of: #{Enum.join(@types, ", ")})"}}
  end
end
