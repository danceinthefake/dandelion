defmodule App.Webhooks.Workers.DeliverTest do
  use Platform.DataCase, async: false
  use Oban.Testing, repo: Platform.Database.Repo

  import App.Webhooks.Fixtures

  alias App.Webhooks.Services.EndpointService
  alias App.Webhooks.Workers.{Deliver, FanOut}
  alias Dandelion.Resilience

  setup do
    # Resilience runs in the application; every test starts with all circuits closed
    :ets.delete_all_objects(Resilience)
    :ok
  end

  defp job_args(endpoint, extra \\ %{}) do
    Map.merge(
      %{
        "endpoint_id" => endpoint.id,
        "event_id" => "evt_order_created_7",
        "type" => "order.created",
        "created_at" => "2026-10-08T00:00:00Z",
        "data" => %{"order_id" => 7, "customer_email" => "sari@example.com"}
      },
      extra
    )
  end

  defp perform(endpoint, extra \\ %{}),
    do: perform_job(Deliver, job_args(endpoint, extra))

  defp stub(status),
    do: Req.Test.stub(App.Webhooks, fn conn -> Plug.Conn.send_resp(conn, status, "") end)

  test "sends the event, signed, and is done on a 2xx" do
    endpoint = endpoint_fixture()
    test = self()

    Req.Test.stub(App.Webhooks, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, conn.request_path, conn.req_headers, body})
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert :ok = perform(endpoint)
    assert_receive {:request, _path, headers, body}

    assert :ok = Dandelion.Webhook.verify(endpoint.secret, headers, body)
    assert {"webhook-id", "evt_order_created_7"} in headers

    assert %{
             "id" => "evt_order_created_7",
             "type" => "order.created",
             "data" => %{"order_id" => 7}
           } = Jason.decode!(body)
  end

  test "a 5xx, 429 or 408 is retried" do
    endpoint = endpoint_fixture()

    for status <- [500, 502, 503, 429, 408] do
      stub(status)
      Resilience.reset({:webhook, URI.parse(endpoint.url).host})
      assert {:error, _} = perform(endpoint), "status #{status}"
    end
  end

  test "any other 4xx is not retried" do
    endpoint = endpoint_fixture()
    stub(400)
    assert {:cancel, "receiver answered 400"} = perform(endpoint)
    assert EndpointService.get(endpoint.id) |> elem(1) |> Map.fetch!(:active)
  end

  test "410 Gone deactivates the endpoint" do
    endpoint = endpoint_fixture()
    stub(410)
    assert {:cancel, _} = perform(endpoint)
    assert {:ok, %{active: false}} = EndpointService.get(endpoint.id)
  end

  test "a connection error is retried" do
    endpoint = endpoint_fixture()
    Req.Test.stub(App.Webhooks, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
    assert {:error, message} = perform(endpoint)
    assert message =~ "request"
  end

  test "after enough failures the circuit opens: nothing is sent, the job waits" do
    endpoint = endpoint_fixture()
    test = self()

    Req.Test.stub(App.Webhooks, fn conn ->
      send(test, :called) && Plug.Conn.send_resp(conn, 500, "")
    end)

    for _ <- 1..5, do: assert({:error, _} = perform(endpoint))
    for _ <- 1..5, do: assert_received(:called)

    assert {:snooze, 30} = perform(endpoint)
    refute_received :called
  end

  test "one dead receiver does not open the circuit for another" do
    dead = endpoint_fixture(%{"url" => "https://dead.example.com/in"})
    fine = endpoint_fixture(%{"url" => "https://fine.example.com/in"})

    Req.Test.stub(App.Webhooks, fn conn ->
      status = if conn.host == "dead.example.com", do: 500, else: 200
      Plug.Conn.send_resp(conn, status, "")
    end)

    for _ <- 1..5, do: perform(dead)
    assert {:snooze, 30} = perform(dead)
    assert :ok = perform(fine)
  end

  test "an endpoint that is gone or off is cancelled, not retried forever" do
    endpoint = endpoint_fixture()
    EndpointService.delete(endpoint.id)
    assert {:cancel, _} = perform(endpoint)
  end

  test "the wait before a retry grows, up to an hour" do
    waits = for attempt <- [1, 2, 3, 20], do: Deliver.backoff(%Oban.Job{attempt: attempt})
    [w1, w2, w3, w20] = waits
    assert w1 in 24..36
    assert w2 in 48..72
    assert w3 in 96..144
    assert w20 in 2_880..4_320
  end

  describe "FanOut" do
    test "one delivery per endpoint that asked for the event, none for others" do
      a = endpoint_fixture()
      b = endpoint_fixture()
      off = endpoint_fixture()
      EndpointService.deactivate(off)

      args = %{"topic" => "order.created", "payload" => %{"order_id" => 9}}
      assert :ok = perform_job(FanOut, args)

      queued = all_enqueued(worker: Deliver) |> Enum.map(& &1.args["endpoint_id"]) |> Enum.sort()
      assert a.id in queued and b.id in queued
      refute off.id in queued

      assert Enum.all?(
               all_enqueued(worker: Deliver),
               &(&1.args["event_id"] == "evt_order_created_9")
             )
    end

    test "running twice queues each delivery once" do
      endpoint = endpoint_fixture()
      args = %{"topic" => "order.created", "payload" => %{"order_id" => 11}}

      assert :ok = perform_job(FanOut, args)
      assert :ok = perform_job(FanOut, args)

      assert [_] =
               all_enqueued(
                 worker: Deliver,
                 args: %{endpoint_id: endpoint.id, event_id: "evt_order_created_11"}
               )
    end
  end
end
