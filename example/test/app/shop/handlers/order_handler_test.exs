defmodule App.Shop.Handlers.OrderHandlerTest do
  use Platform.ConnCase, async: true

  import App.Shop.Fixtures

  test "POST /api/orders creates an order", %{conn: conn} do
    conn = post(conn, "/api/orders", order_params())

    assert %{
             "id" => _,
             "status" => "pending",
             "total_cents" => 7000,
             "items" => [%{"sku" => "TEA-01", "quantity" => 2, "price_cents" => 1500}, _]
           } = json_response(conn, 201)
  end

  test "POST /api/orders with invalid input is 422 with field errors", %{conn: conn} do
    conn =
      post(
        conn,
        "/api/orders",
        order_params(%{"customer_email" => "", "items" => [%{"sku" => "TEA-01"}]})
      )

    assert json_response(conn, 422) == %{
             "errors" => %{
               "customer_email" => ["can't be blank"],
               "items" => [%{"quantity" => ["can't be blank"]}]
             }
           }
  end

  test "POST /api/orders takes prices from the products, not the request", %{conn: conn} do
    items = [%{"sku" => "TEA-01", "quantity" => 1, "price_cents" => 1}]
    conn = post(conn, "/api/orders", order_params(%{"items" => items}))

    assert %{"total_cents" => 1500, "items" => [%{"price_cents" => 1500}]} =
             json_response(conn, 201)
  end

  test "POST /api/orders with an unknown product is 400", %{conn: conn} do
    items = [%{"sku" => "NOPE", "quantity" => 1}]
    conn = post(conn, "/api/orders", order_params(%{"items" => items}))
    assert %{"error" => "unknown product: NOPE"} = json_response(conn, 400)
  end

  test "POST /api/orders refuses numbers too big to store", %{conn: conn} do
    for {items, field} <- [
          {[%{"sku" => "TEA-01", "quantity" => 3_000_000_000}], "items"},
          {List.duplicate(%{"sku" => "BIG-99", "quantity" => 1_000_000}, 2), "total_cents"}
        ] do
      conn = post(conn, "/api/orders", order_params(%{"items" => items}))
      assert %{"errors" => %{^field => _}} = json_response(conn, 422)
    end
  end

  test "GET /api/orders/:id, and 404 for unknown or malformed ids", %{conn: conn} do
    order = order_fixture()
    assert %{"id" => id} = conn |> get("/api/orders/#{order.id}") |> json_response(200)
    assert id == order.id

    assert %{"error" => "not found"} = conn |> get("/api/orders/999999") |> json_response(404)
    assert %{"error" => "not found"} = conn |> get("/api/orders/abc") |> json_response(404)

    assert %{"error" => "not found"} =
             conn |> get("/api/orders/99999999999999999999") |> json_response(404)
  end

  test "GET /api/orders pages and filters; bad parameters are 400", %{conn: conn} do
    order_fixture(status: "paid")

    assert %{"orders" => [%{"status" => "paid"}], "page" => 1, "per_page" => 20} =
             conn |> get("/api/orders?status=paid") |> json_response(200)

    assert %{"error" => "status must be one of" <> _} =
             conn |> get("/api/orders?status=lost") |> json_response(400)
  end

  test "POST /api/orders/:id/cancel, and 409 when the rule says no", %{conn: conn} do
    assert %{"status" => "cancelled"} =
             conn |> post("/api/orders/#{order_fixture().id}/cancel") |> json_response(200)

    assert %{"error" => "a shipped order can't be cancelled"} =
             conn
             |> post("/api/orders/#{order_fixture(status: "shipped").id}/cancel")
             |> json_response(409)
  end
end
