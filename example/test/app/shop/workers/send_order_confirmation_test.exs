defmodule App.Shop.Workers.SendOrderConfirmationTest do
  use Platform.DataCase, async: true
  use Oban.Testing, repo: Platform.Database.Repo

  import App.Shop.Fixtures
  import ExUnit.CaptureLog

  alias App.Shop.Services.OrderService
  alias App.Shop.Workers.SendOrderConfirmation

  test "creating an order queues its confirmation" do
    {:ok, order} = OrderService.create(order_params())
    assert_enqueued(worker: SendOrderConfirmation, args: %{order_id: order.id})
  end

  test "an invalid order queues nothing" do
    assert {:error, %Ecto.Changeset{}} = OrderService.create(%{})
    refute_enqueued(worker: SendOrderConfirmation)
  end

  test "sends the confirmation" do
    order = order_fixture()
    # the test logger drops :info
    Logger.put_module_level(SendOrderConfirmation, :info)
    on_exit(fn -> Logger.delete_module_level(SendOrderConfirmation) end)

    log =
      capture_log(fn ->
        assert :ok = perform_job(SendOrderConfirmation, %{order_id: order.id})
      end)

    assert log =~ "confirmation sent to sari@example.com"
  end

  test "cancels for an order that doesn't exist" do
    assert {:cancel, _} = perform_job(SendOrderConfirmation, %{order_id: 0})
  end
end
