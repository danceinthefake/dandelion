defmodule Platform.PubSubTest do
  use Platform.DataCase, async: true
  use Oban.Testing, repo: Platform.Database.Repo

  import App.Shop.Fixtures

  alias App.Shop.Services.OrderService
  alias App.Shop.Workers.{SendOrderConfirmation, UpdateCustomerStats}
  alias Platform.Database.Repo

  test "an order is published to every subscriber of order.created" do
    {:ok, order} = OrderService.create(order_params())
    payload = %{order_id: order.id, customer_email: "sari@example.com"}

    for worker <- [SendOrderConfirmation, UpdateCustomerStats] do
      assert_enqueued(worker: worker, args: %{topic: "order.created", payload: payload})
    end
  end

  test "an invalid order publishes nothing" do
    assert {:error, %Ecto.Changeset{}} = OrderService.create(%{})
    refute_enqueued(worker: SendOrderConfirmation)
    refute_enqueued(worker: UpdateCustomerStats)
  end

  test "the event is saved with the order or not at all" do
    Repo.transact(fn ->
      {:ok, _} = OrderService.create(order_params(%{"customer_email" => "rolled@example.com"}))
      Repo.rollback(:oops)
    end)

    refute_enqueued(
      worker: SendOrderConfirmation,
      args: %{payload: %{customer_email: "rolled@example.com"}}
    )
  end

  test "an order is broadcast live after it is saved" do
    Phoenix.PubSub.subscribe(Platform.Broadcast, "orders")
    {:ok, order} = OrderService.create(order_params())
    assert_receive {:order_created, id} when id == order.id
  end

  test "every topic's subscribers are Oban workers" do
    for {_topic, workers} <- Platform.PubSub.subscriptions(), worker <- workers do
      assert Code.ensure_loaded?(worker) and function_exported?(worker, :perform, 1)
    end
  end
end
