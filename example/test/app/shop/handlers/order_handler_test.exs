defmodule App.Shop.Handlers.OrderHandlerTest do
  use Platform.ConnCase, async: true

  import App.Accounts.Fixtures
  import App.Shop.Fixtures

  # every test is a logged-in customer
  setup %{conn: conn} do
    user = user_fixture()
    {:ok, conn: log_in(conn, user), user: user}
  end

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

  test "GET /api/orders/:id, and 404 for unknown or malformed ids", %{conn: conn, user: user} do
    order = order_fixture(user_id: user.id)
    assert %{"id" => id} = conn |> get("/api/orders/#{order.id}") |> json_response(200)
    assert id == order.id

    assert %{"error" => "not found"} = conn |> get("/api/orders/999999") |> json_response(404)
    assert %{"error" => "not found"} = conn |> get("/api/orders/abc") |> json_response(404)

    assert %{"error" => "not found"} =
             conn |> get("/api/orders/99999999999999999999") |> json_response(404)
  end

  test "GET /api/orders pages and filters; bad parameters are 400", %{conn: conn, user: user} do
    order_fixture(status: "paid", user_id: user.id)

    assert %{"orders" => [%{"status" => "paid"}], "page" => 1, "per_page" => 20} =
             conn |> get("/api/orders?status=paid") |> json_response(200)

    assert %{"error" => "status must be one of" <> _} =
             conn |> get("/api/orders?status=lost") |> json_response(400)
  end

  test "POST /api/orders/:id/cancel, and 409 when the rule says no", %{conn: conn, user: user} do
    assert %{"status" => "cancelled"} =
             conn
             |> post("/api/orders/#{order_fixture(user_id: user.id).id}/cancel")
             |> json_response(200)

    assert %{"error" => "a shipped order can't be cancelled"} =
             conn
             |> post(
               "/api/orders/#{order_fixture(status: "shipped", user_id: user.id).id}/cancel"
             )
             |> json_response(409)
  end

  describe "Idempotency-Key" do
    defp keyed(conn, key), do: Plug.Conn.put_req_header(conn, "idempotency-key", key)

    test "a retry with the same key and body returns the same order, once", %{conn: conn} do
      first = conn |> keyed("k-1") |> post("/api/orders", order_params())
      %{"id" => id} = json_response(first, 201)

      second = conn |> keyed("k-1") |> post("/api/orders", order_params())
      assert %{"id" => ^id} = json_response(second, 200)
      assert Plug.Conn.get_resp_header(second, "idempotent-replayed") == ["true"]
      assert Plug.Conn.get_resp_header(first, "idempotent-replayed") == []

      assert %{"orders" => [%{"id" => ^id}]} =
               conn |> get("/api/orders") |> json_response(200)
    end

    test "the same key with another request is a 409, and makes nothing", %{conn: conn} do
      conn |> keyed("k-2") |> post("/api/orders", order_params()) |> json_response(201)

      other = order_params(%{"customer_email" => "someone-else@example.com"})

      assert %{"error" => message} =
               conn |> keyed("k-2") |> post("/api/orders", other) |> json_response(409)

      assert message =~ "Idempotency-Key"
      assert %{"orders" => [_]} = conn |> get("/api/orders") |> json_response(200)
    end

    test "without a key, two identical requests are two orders", %{conn: conn} do
      post(conn, "/api/orders", order_params()) |> json_response(201)
      post(conn, "/api/orders", order_params()) |> json_response(201)
      assert %{"orders" => [_, _]} = conn |> get("/api/orders") |> json_response(200)
    end

    test "a request that failed validation made nothing: the key can be used again", %{conn: conn} do
      bad = order_params(%{"customer_email" => ""})
      conn |> keyed("k-3") |> post("/api/orders", bad) |> json_response(422)
      conn |> keyed("k-3") |> post("/api/orders", order_params()) |> json_response(201)
    end

    test "keys are per customer", %{conn: conn} do
      conn |> keyed("k-4") |> post("/api/orders", order_params()) |> json_response(201)

      other = Phoenix.ConnTest.build_conn() |> log_in(user_fixture())

      assert %{"id" => _} =
               other |> keyed("k-4") |> post("/api/orders", order_params()) |> json_response(201)
    end

    test "a key that is empty or too long is a 400", %{conn: conn} do
      assert conn |> keyed("") |> post("/api/orders", order_params()) |> json_response(400)
      long = String.duplicate("x", 256)
      assert conn |> keyed(long) |> post("/api/orders", order_params()) |> json_response(400)
    end
  end
end
