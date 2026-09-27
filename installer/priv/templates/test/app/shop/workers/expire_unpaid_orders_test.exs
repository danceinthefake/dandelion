defmodule App.Shop.Workers.ExpireUnpaidOrdersTest do
  use Platform.DataCase, async: true

  import App.Shop.Fixtures

  alias App.Shop.Services.OrderService
  alias App.Shop.Workers.ExpireUnpaidOrders
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    # A private instance per test (the app's own one is off in tests).
    job =
      start_supervised!(
        {ExpireUnpaidOrders, name: nil, max_age_seconds: 3600, every_seconds: 3600},
        id: make_ref()
      )

    # The job is its own process: let it use this test's database sandbox.
    Sandbox.allow(Platform.Database.Repo, self(), job)
    %{job: job}
  end

  test "run_now cancels unpaid orders older than the limit", %{job: job} do
    old = order_fixture(inserted_at: DateTime.add(DateTime.utc_now(), -2, :hour))
    fresh = order_fixture()

    assert ExpireUnpaidOrders.run_now(job) == 1
    assert {:ok, %{status: "cancelled"}} = OrderService.get(old.id)
    assert {:ok, %{status: "pending"}} = OrderService.get(fresh.id)
  end

  test "if the job crashes, its supervisor starts a new one that keeps working" do
    name = :"expire_#{System.unique_integer([:positive])}"
    start_supervised!({ExpireUnpaidOrders, name: name, every_seconds: 3600}, id: name)
    old = Process.whereis(name)

    Process.exit(old, :kill)
    new = wait_for_restart(name, old)

    assert new != old
    Sandbox.allow(Platform.Database.Repo, self(), new)
    order_fixture(inserted_at: DateTime.add(DateTime.utc_now(), -2, :hour))
    assert ExpireUnpaidOrders.run_now(name) == 1
  end

  defp wait_for_restart(name, old, tries \\ 50) do
    case Process.whereis(name) do
      pid when is_pid(pid) and pid != old -> pid
      _ when tries > 0 -> Process.sleep(10) && wait_for_restart(name, old, tries - 1)
      _ -> flunk("#{name} was not restarted")
    end
  end
end
