defmodule App.Shop.Workers.SendOrderConfirmation do
  @moduledoc """
  Subscriber of `order.created` (`Platform.PubSub`): emails the customer "we got your
  order" (`App.Notifications.Services.EmailService`).

  ≈ in Go, a Google Pub/Sub subscription handler. It is retried if it fails, runs on any
  node, and is run again if its node dies mid-job — so sending must be safe twice: the
  email service writes the message under a key (`order_confirmation:<id>`) and sends it
  once.

  A mail server that is down never holds up the order: it was saved and answered long
  before this job runs. Here, the job waits (`{:snooze, 30}` while the circuit for that
  server is open, a retry with backoff otherwise), and a server that refuses the address for
  good ends the job (`{:cancel, …}`) instead of retrying a mistake.
  """
  use Oban.Worker, queue: :mail, max_attempts: 10

  alias App.Notifications.Services.EmailService
  alias App.Shop.Services.OrderService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payload" => %{"order_id" => id}}}) do
    case OrderService.get(id) do
      {:ok, order} ->
        key = "order_confirmation:#{order.id}"

        case EmailService.send_once(
               key,
               "order_confirmation",
               order.customer_email,
               "Your order ##{order.id}",
               body(order)
             ) do
          :ok -> :ok
          {:error, :circuit_open} -> {:snooze, 30}
          {:error, {:permanent, why}} -> {:cancel, "the mail server refused it: #{why}"}
          {:error, {:temporary, why}} -> {:error, why}
        end

      # the order is gone; nothing to confirm
      {:error, :not_found} ->
        {:cancel, "order #{id} not found"}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    base = Application.get_env(:acme, :mail_backoff_seconds, 30)
    wait = min(base * Integer.pow(2, attempt - 1), 3_600)
    round(wait * (0.8 + :rand.uniform() * 0.4))
  end

  defp body(order) do
    lines =
      Enum.map_join(order.items, "\n", fn i ->
        "  #{i.quantity} x #{i.sku}   #{money(i.price_cents * i.quantity)}"
      end)

    """
    Hello,

    Thank you for your order ##{order.id}. We have it, and will tell you when it is paid and on its way.

    #{lines}

    Total: #{money(order.total_cents)}
    """
  end

  defp money(cents),
    do: :io_lib.format("~B.~2..0B", [div(cents, 100), rem(cents, 100)]) |> IO.iodata_to_binary()
end
