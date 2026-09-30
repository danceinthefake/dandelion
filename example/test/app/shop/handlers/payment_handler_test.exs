defmodule App.Shop.Handlers.PaymentHandlerTest do
  use Platform.ConnCase, async: true
  use Oban.Testing, repo: Platform.Database.Repo

  alias App.Shop.Workers.ProcessPaymentEvent

  @event %{"event_id" => "evt-handler-1", "type" => "payment.succeeded", "order_id" => 777_001}

  defp post_event(conn, params, token \\ "test-token") do
    conn |> put_req_header("x-callback-token", token) |> post("/api/payments/webhook", params)
  end

  test "an event with the right token is accepted and queued on its order's line", %{conn: conn} do
    assert %{"status" => "accepted"} = conn |> post_event(@event) |> json_response(202)
    assert_enqueued(worker: ProcessPaymentEvent, args: @event, queue: :ordered)

    assert [%{meta: %{"ordered_key" => "order:777001"}}] =
             all_enqueued(worker: ProcessPaymentEvent, args: @event)
  end

  test "a wrong or missing token is 401 and queues nothing", %{conn: conn} do
    assert conn |> post_event(@event, "nope") |> json_response(401)
    assert build_conn() |> post("/api/payments/webhook", @event) |> json_response(401)
    refute_enqueued(worker: ProcessPaymentEvent)
  end

  test "an event that isn't valid is 400", %{conn: conn} do
    for bad <- [
          %{},
          %{@event | "type" => "payment.exploded"},
          %{@event | "order_id" => "7"},
          %{@event | "event_id" => ""}
        ] do
      assert %{"error" => _} = conn |> post_event(bad) |> json_response(400)
    end
  end
end
