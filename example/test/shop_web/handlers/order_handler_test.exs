defmodule ShopWeb.Handlers.OrderHandlerTest do
  use ShopWeb.ConnCase, async: true

  import Shop.Fixtures

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
        order_params(%{"customer_email" => "", "items" => [%{"sku" => "A"}]})
      )

    assert json_response(conn, 422) == %{
             "errors" => %{
               "customer_email" => ["can't be blank"],
               "items" => [
                 %{"quantity" => ["can't be blank"], "price_cents" => ["can't be blank"]}
               ]
             }
           }
  end

  test "GET /api/orders/:id, and 404 for unknown or malformed ids", %{conn: conn} do
    order = order_fixture()
    assert %{"id" => id} = conn |> get("/api/orders/#{order.id}") |> json_response(200)
    assert id == order.id

    assert %{"error" => "not found"} = conn |> get("/api/orders/999999") |> json_response(404)
    assert %{"error" => "not found"} = conn |> get("/api/orders/abc") |> json_response(404)
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
