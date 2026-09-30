defmodule App.Shop.Workers.ProcessPaymentEventTest do
  use Platform.DataCase, async: true
  use Oban.Testing, repo: Platform.Database.Repo

  import App.Shop.Fixtures
  import ExUnit.CaptureLog

  alias App.Shop.Services.{OrderService, PaymentService}
  alias App.Shop.Workers.ProcessPaymentEvent
  alias Platform.Database.Repo

  defp event(order, type, n),
    do: %{"event_id" => "evt-#{order.id}-#{n}", "type" => type, "order_id" => order.id}

  defp status(order), do: (fn {:ok, o} -> o.status end).(OrderService.get(order.id))

  defp queued(order) do
    all_enqueued(worker: ProcessPaymentEvent)
    |> Enum.filter(&(&1.args["order_id"] == order.id))
    |> Enum.sort_by(& &1.id)
  end

  # runs a queued job the way the queue would, then marks it done
  defp run(job) do
    result = ProcessPaymentEvent.perform(job)

    if result == :ok,
      do: Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: "completed"])

    result
  end

  test "a payment marks the order paid, a refund marks it refunded" do
    order = order_fixture()
    :ok = PaymentService.receive_event(event(order, "payment.succeeded", 1))
    :ok = PaymentService.receive_event(event(order, "payment.refunded", 2))

    for job <- queued(order), do: assert(:ok = run(job))
    assert status(order) == "refunded"
  end

  test "each event waits for the one before it" do
    order = order_fixture()
    :ok = PaymentService.receive_event(event(order, "payment.succeeded", 1))
    :ok = PaymentService.receive_event(event(order, "payment.refunded", 2))
    [first, second] = queued(order)

    assert {:snooze, 1} = run(second)
    assert status(order) == "pending"
    assert :ok = run(first)
    assert status(order) == "paid"
    assert :ok = run(second)
    assert status(order) == "refunded"
  end

  test "the same event twice is queued once" do
    order = order_fixture()
    e = event(order, "payment.succeeded", 1)
    :ok = PaymentService.receive_event(e)
    :ok = PaymentService.receive_event(e)
    assert [_] = queued(order)
  end

  test "a payment for a cancelled order is dropped, not retried" do
    order = order_fixture(status: "cancelled")

    log =
      capture_log(fn ->
        assert :ok =
                 perform_job(ProcessPaymentEvent, event(order, "payment.succeeded", 1),
                   meta: %{"ordered_key" => "order:#{order.id}"}
                 )
      end)

    assert log =~ "dropped"
    assert status(order) == "cancelled"
  end

  test "an order that doesn't exist cancels the job" do
    assert {:cancel, _} =
             perform_job(
               ProcessPaymentEvent,
               %{"event_id" => "e", "type" => "payment.succeeded", "order_id" => 0},
               meta: %{"ordered_key" => "order:0"}
             )
  end
end
