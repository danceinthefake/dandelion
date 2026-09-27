defmodule Shop.Services.OrderServiceTest do
  use Shop.DataCase, async: true

  import Shop.Fixtures

  alias Shop.Services.OrderService

  defp errors(changeset), do: Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)

  describe "create/1" do
    test "creates the order with its items and computes the total" do
      assert {:ok, order} = OrderService.create(order_params())
      assert order.status == "pending"
      assert order.total_cents == 2 * 1500 + 4000
      assert [%{sku: "TEA-01"}, %{sku: "CUP-02"}] = order.items
    end

    # Table-driven, like a Go `for _, tc := range cases`.
    test "rejects invalid input" do
      cases = [
        {"missing email", %{"customer_email" => nil}, %{customer_email: ["can't be blank"]}},
        {"bad email", %{"customer_email" => "sari"},
         %{customer_email: ["must be an email address"]}},
        {"no items", %{"items" => []}, %{items: ["can't be blank"]}},
        {"zero quantity", %{"items" => [%{"sku" => "A", "quantity" => 0, "price_cents" => 1}]},
         %{items: [%{quantity: ["must be greater than %{number}"]}]}},
        {"negative price", %{"items" => [%{"sku" => "A", "quantity" => 1, "price_cents" => -5}]},
         %{items: [%{price_cents: ["must be greater than or equal to %{number}"]}]}}
      ]

      for {name, overrides, expected} <- cases do
        assert {:error, changeset} = OrderService.create(order_params(overrides)), name
        assert errors(changeset) == expected, name
      end
    end
  end

  describe "get/1" do
    test "finds an order, or :not_found" do
      order = order_fixture()
      assert {:ok, %{id: id}} = OrderService.get(order.id)
      assert id == order.id
      assert OrderService.get(-1) == {:error, :not_found}
    end
  end

  describe "list/1" do
    test "filters by status and pages newest first" do
      old = order_fixture(inserted_at: ~U[2026-01-01 00:00:00.000000Z])
      new = order_fixture()
      shipped = order_fixture(status: "shipped")

      assert {:ok, %{orders: pending}} = OrderService.list(%{"status" => "pending"})
      assert Enum.map(pending, & &1.id) == [new.id, old.id]

      assert {:ok, %{orders: [%{id: id}], page: 1, per_page: 1}} =
               OrderService.list(%{"per_page" => "1"})

      assert id == shipped.id

      assert {:ok, %{orders: [%{id: id}]}} =
               OrderService.list(%{"per_page" => "1", "page" => "3"})

      assert id == old.id
    end

    test "rejects bad parameters" do
      for params <- [
            %{"status" => "lost"},
            %{"page" => "0"},
            %{"page" => "x"},
            %{"page" => "99999999999999999999"},
            %{"page" => %{"x" => "1"}},
            %{"per_page" => "101"}
          ] do
        assert {:error, {:invalid, _message}} = OrderService.list(params), inspect(params)
      end
    end
  end

  describe "cancel/1" do
    test "pending and paid orders can be cancelled" do
      for status <- ["pending", "paid"] do
        order = order_fixture(status: status)
        assert {:ok, %{status: "cancelled"}} = OrderService.cancel(order.id), status
      end
    end

    test "shipped or already cancelled orders can't" do
      assert {:error, {:conflict, "a shipped order can't be cancelled"}} =
               OrderService.cancel(order_fixture(status: "shipped").id)

      assert {:error, {:conflict, "the order is already cancelled"}} =
               OrderService.cancel(order_fixture(status: "cancelled").id)
    end

    test "missing order" do
      assert OrderService.cancel(-1) == {:error, :not_found}
    end
  end

  describe "expire_unpaid/1" do
    test "cancels only pending orders older than the limit" do
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)
      old_pending = order_fixture(inserted_at: two_hours_ago)
      old_paid = order_fixture(status: "paid", inserted_at: two_hours_ago)
      fresh = order_fixture()

      assert OrderService.expire_unpaid(3600) == 1

      assert {:ok, %{status: "cancelled"}} = OrderService.get(old_pending.id)
      assert {:ok, %{status: "paid"}} = OrderService.get(old_paid.id)
      assert {:ok, %{status: "pending"}} = OrderService.get(fresh.id)
    end
  end
end
