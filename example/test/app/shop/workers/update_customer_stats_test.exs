defmodule App.Shop.Workers.UpdateCustomerStatsTest do
  use Platform.DataCase, async: true
  use Oban.Testing, repo: Platform.Database.Repo

  import App.Shop.Fixtures

  alias App.Shop.Workers.UpdateCustomerStats
  alias Platform.Database.Repos.CustomerRepo

  @email "stats-test@example.com"

  test "counts the customer's orders, and gives the same answer when run again" do
    assert CustomerRepo.orders_count(@email) == 0

    for _ <- 1..3, do: order_fixture(email: @email)

    args = %{payload: %{customer_email: @email}}
    assert :ok = perform_job(UpdateCustomerStats, args)
    assert CustomerRepo.orders_count(@email) == 3

    assert :ok = perform_job(UpdateCustomerStats, args)
    assert CustomerRepo.orders_count(@email) == 3
  end
end
