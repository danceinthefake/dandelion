defmodule App.Settings.Handlers.FlagHandlerTest do
  use Platform.ConnCase, async: false

  import App.Accounts.Fixtures
  import App.Shop.Fixtures

  alias Dandelion.Cache

  # the cache is shared by all tests: leave no flag behind in it
  setup do
    on_exit(fn -> Cache.delete({:flag, "orders.enabled"}) end)
  end

  test "only an admin changes flags", %{conn: conn} do
    assert conn |> put("/api/flags/orders.enabled", %{"value" => false}) |> json_response(401)

    assert conn
           |> log_in(user_fixture())
           |> put("/api/flags/orders.enabled", %{"value" => false})
           |> json_response(403)
  end

  test "set, list and unset a flag", %{conn: conn} do
    conn = log_in(conn, admin_fixture())

    assert %{"key" => "search.page_size", "value" => 50} =
             conn |> put("/api/flags/search.page_size", %{"value" => 50}) |> json_response(200)

    assert %{"flags" => flags} = conn |> get("/api/flags") |> json_response(200)
    assert %{"value" => 50} = Enum.find(flags, &(&1["key"] == "search.page_size"))

    assert conn |> delete("/api/flags/search.page_size") |> response(204)
    assert %{"flags" => flags} = conn |> get("/api/flags") |> json_response(200)
    refute Enum.any?(flags, &(&1["key"] == "search.page_size"))
  end

  test "a bad key or a request without a value is a 400", %{conn: conn} do
    conn = log_in(conn, admin_fixture())
    assert conn |> put("/api/flags/Bad Key", %{"value" => 1}) |> json_response(400)
    assert conn |> put("/api/flags/ok.key", %{}) |> json_response(400)
  end

  test "pausing orders: new orders are a 503 with retry-after, until turned back on", %{
    conn: conn
  } do
    admin = log_in(conn, admin_fixture())
    customer = log_in(Phoenix.ConnTest.build_conn(), user_fixture())

    admin |> put("/api/flags/orders.enabled", %{"value" => false}) |> json_response(200)

    paused = post(customer, "/api/orders", order_params())
    assert %{"error" => message} = json_response(paused, 503)
    assert message =~ "paused"
    assert Plug.Conn.get_resp_header(paused, "retry-after") == ["30"]

    # reading is not paused
    assert customer |> get("/api/orders") |> json_response(200)

    admin |> put("/api/flags/orders.enabled", %{"value" => true}) |> json_response(200)
    assert customer |> post("/api/orders", order_params()) |> json_response(201)
  end
end
