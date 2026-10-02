defmodule App.Shop.Handlers.ProductHandlerTest do
  use Platform.ConnCase, async: true

  import App.Accounts.Fixtures
  import App.Shop.Fixtures

  test "GET /api/products/:sku", %{conn: conn} do
    p = product_fixture(%{name: "Green tea"})

    assert json_response(get(conn, "/api/products/#{p.sku}"), 200) ==
             %{"sku" => p.sku, "name" => "Green tea", "price_cents" => 1500}
  end

  test "PUT /api/products/:sku (as an admin) changes the price, and GET shows it", %{conn: conn} do
    p = product_fixture()
    assert get(conn, "/api/products/#{p.sku}").status == 200
    admin = log_in(conn, admin_fixture())

    assert %{"price_cents" => 1600} =
             admin
             |> put("/api/products/#{p.sku}", %{"price_cents" => 1600})
             |> json_response(200)

    assert %{"price_cents" => 1600} = conn |> get("/api/products/#{p.sku}") |> json_response(200)
  end

  test "unknown product is 404; a bad price is 422", %{conn: conn} do
    assert json_response(get(conn, "/api/products/NOPE"), 404)
    p = product_fixture()
    admin = log_in(conn, admin_fixture())

    assert %{"errors" => %{"price_cents" => _}} =
             admin |> put("/api/products/#{p.sku}", %{"price_cents" => -5}) |> json_response(422)
  end
end
