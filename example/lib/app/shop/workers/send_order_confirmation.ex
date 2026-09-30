defmodule App.Shop.Workers.SendOrderConfirmation do
  @moduledoc """
  Subscriber of `order.created` (`Platform.PubSub`): sends the "we got your
  order" message. There is no mail server here: the message is logged where
  a real one would be sent.

  ≈ in Go, a Google Pub/Sub subscription handler. It is retried if it fails,
  runs on any node, and is run again if its node dies mid-job — so sending
  must be safe twice (at least once, like every queue).
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  require Logger

  alias App.Shop.Services.OrderService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payload" => %{"order_id" => id}}}) do
    case OrderService.get(id) do
      {:ok, order} ->
        Logger.info("order ##{order.id}: confirmation sent to #{order.customer_email}")
        :ok

      # the order is gone; nothing to confirm
      {:error, :not_found} ->
        {:cancel, "order #{id} not found"}
    end
  end
end
