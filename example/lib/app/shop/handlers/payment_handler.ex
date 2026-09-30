defmodule App.Shop.Handlers.PaymentHandler do
  @moduledoc """
  The payment provider's webhook. ≈ `http/payments.go`.

  The provider sends its secret in the `x-callback-token` header (as Xendit
  does; Midtrans and Stripe sign the body instead). Anything without the
  right token is 401.
  """
  use Platform.Web, :handler

  alias App.Shop.Services.PaymentService

  action_fallback Platform.Web.FallbackHandler

  plug :verify_token

  # POST /api/payments/webhook
  # {"event_id": "evt_1", "type": "payment.succeeded", "order_id": 42}
  def webhook(conn, params) do
    with :ok <- PaymentService.receive_event(params) do
      conn |> put_status(:accepted) |> json(%{status: "accepted"})
    end
  end

  defp verify_token(conn, _opts) do
    expected = Application.fetch_env!(:acme, :payment_webhook_token)
    given = conn |> get_req_header("x-callback-token") |> List.first("")

    if Plug.Crypto.secure_compare(given, expected) do
      conn
    else
      conn |> put_status(:unauthorized) |> json(%{error: "bad token"}) |> halt()
    end
  end
end
