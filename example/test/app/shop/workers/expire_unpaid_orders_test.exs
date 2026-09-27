defmodule App.Shop.Workers.ExpireUnpaidOrdersTest do
  use Platform.DataCase, async: true
  use Oban.Testing, repo: Platform.Database.Repo

  import App.Shop.Fixtures

  alias App.Shop.Services.OrderService
  alias App.Shop.Workers.ExpireUnpaidOrders

  test "cancels unpaid orders older than the limit" do
    old = order_fixture(inserted_at: DateTime.add(DateTime.utc_now(), -2, :hour))
    fresh = order_fixture()

    assert :ok = perform_job(ExpireUnpaidOrders, %{})
    assert {:ok, %{status: "cancelled"}} = OrderService.get(old.id)
    assert {:ok, %{status: "pending"}} = OrderService.get(fresh.id)
  end

  test "is scheduled every minute" do
    assert {"* * * * *", ExpireUnpaidOrders} in Platform.Cron.schedule()
  end
end
