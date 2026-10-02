defmodule App.Shop.Handlers.OrderAccessTest do
  @moduledoc "Who may do what: logins, ownership and roles, on every route."
  use Platform.ConnCase, async: true

  import App.Accounts.Fixtures
  import App.Shop.Fixtures

  alias App.Shop.Services.OrderService

  describe "without a login" do
    test "every order route is 401", %{conn: conn} do
      for {method, path} <- [
            {:post, "/api/orders"},
            {:get, "/api/orders"},
            {:get, "/api/orders/1"},
            {:post, "/api/orders/1/cancel"},
            {:get, "/api/me"},
            {:put, "/api/products/TEA-01"}
          ] do
        assert %{"error" => "unauthorized"} =
                 conn |> dispatch(method, path) |> json_response(401)
      end
    end

    test "what is public stays public: the catalogue, health, the webhook has its own token", %{
      conn: conn
    } do
      assert get(conn, "/api/products/TEA-01").status == 200
      assert get(conn, "/health").status == 200
      assert post(conn, "/api/payments/webhook", %{}).status == 401
    end
  end

  describe "a customer" do
    setup %{conn: conn} do
      me = user_fixture()
      other = user_fixture()
      {:ok, me: me, other: other, conn: log_in(conn, me)}
    end

    test "sees their own orders and not somebody else's", %{conn: conn, me: me, other: other} do
      mine = order_fixture(user_id: me.id)
      theirs = order_fixture(user_id: other.id)
      nobody = order_fixture()

      assert %{"orders" => orders} = conn |> get("/api/orders") |> json_response(200)
      assert Enum.map(orders, & &1["id"]) == [mine.id]

      assert conn |> get("/api/orders/#{mine.id}") |> json_response(200)
      # somebody else's order and a missing one look the same
      for id <- [theirs.id, nobody.id, 0] do
        assert %{"error" => "not found"} = conn |> get("/api/orders/#{id}") |> json_response(404)
      end
    end

    test "can't cancel somebody else's order, and it is left alone", %{conn: conn, other: other} do
      theirs = order_fixture(user_id: other.id)

      assert %{"error" => "not found"} =
               conn |> post("/api/orders/#{theirs.id}/cancel") |> json_response(404)

      assert {:ok, %{status: "pending"}} = OrderService.get(theirs.id)
    end

    test "an order they make is theirs — whatever the request says", %{
      conn: conn,
      me: me,
      other: other
    } do
      params = order_params(%{"user_id" => other.id, "role" => "admin"})
      assert %{"id" => id} = conn |> post("/api/orders", params) |> json_response(201)

      assert {:ok, %{user_id: owner}} = OrderService.get(id)
      assert owner == me.id
    end

    test "can't change a price: 403", %{conn: conn} do
      assert %{"error" => "forbidden"} =
               conn |> put("/api/products/TEA-01", %{"price_cents" => 1}) |> json_response(403)
    end
  end

  describe "an admin" do
    setup %{conn: conn} do
      admin = admin_fixture()
      {:ok, admin: admin, conn: log_in(conn, admin)}
    end

    test "sees every order, and can cancel any", %{conn: conn} do
      one = order_fixture(user_id: user_fixture().id)
      two = order_fixture()

      assert %{"orders" => orders} = conn |> get("/api/orders") |> json_response(200)
      ids = Enum.map(orders, & &1["id"])
      assert one.id in ids and two.id in ids

      assert %{"status" => "cancelled"} =
               conn |> post("/api/orders/#{one.id}/cancel") |> json_response(200)
    end

    test "can change a price", %{conn: conn} do
      product = product_fixture()

      assert %{"price_cents" => 1700} =
               conn
               |> put("/api/products/#{product.sku}", %{"price_cents" => 1700})
               |> json_response(200)
    end
  end

  defp dispatch(conn, method, path),
    do: Phoenix.ConnTest.dispatch(conn, Platform.Web.Endpoint, method, path)
end
