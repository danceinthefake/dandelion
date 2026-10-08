defmodule App.Shop.Handlers.ProductSearchHandlerTest do
  use Platform.ConnCase, async: true

  import App.Accounts.Fixtures
  import App.Shop.Fixtures

  # a word nobody else's test uses, so these tests do not see each other's products
  defp tag, do: "zq#{System.unique_integer([:positive])}"

  defp search(conn, query),
    do: conn |> get("/api/search/products?" <> URI.encode_query(query)) |> json_response(200)

  defp skus(result), do: Enum.map(result["results"], & &1["sku"])

  test "finds products by words in the name or description, with a snippet", %{conn: conn} do
    t = tag()

    green =
      product_fixture(%{
        name: "#{t} Green tea",
        description: "Fresh leaves from the hills, picked by hand each morning"
      })

    cup =
      product_fixture(%{
        name: "#{t} Cup",
        description: "Holds green tea or anything else you like to drink"
      })

    _other = product_fixture(%{name: "#{t} Sugar"})

    result = search(conn, q: "#{t} green")
    assert result["match"] == "text" and result["total"] == 2
    # the name outranks the description
    assert skus(result) == [green.sku, cup.sku]
    [first, second] = result["results"]
    assert first["rank"] > second["rank"]
    assert second["snippet"] =~ "[[green]]"
    assert %{"name" => _, "price_cents" => 1500} = first
  end

  test "every word is a prefix and all must match", %{conn: conn} do
    t = tag()
    p = product_fixture(%{name: "#{t} Green tea"})
    product_fixture(%{name: "#{t} Black tea"})

    assert skus(search(conn, q: "#{t} gre te")) == [p.sku]
    assert search(conn, q: "#{t} green coffee")["match"] != "text"
  end

  test "a typo falls back to similar names, and says so", %{conn: conn} do
    t = tag()
    p = product_fixture(%{name: "#{t}green tea"})
    result = search(conn, q: "#{t}grean tea")
    assert result["match"] == "fuzzy"
    assert p.sku in skus(result)
  end

  test "accents and case do not matter", %{conn: conn} do
    t = tag()
    p = product_fixture(%{name: "#{t} Café crème"})
    assert p.sku in skus(search(conn, q: "#{String.upcase(t)} CAFE creme"))
  end

  test "paging, and the total", %{conn: conn} do
    t = tag()
    for i <- 1..5, do: product_fixture(%{name: "#{t} item #{i}"})

    page1 = search(conn, q: t, limit: 2)
    page2 = search(conn, q: t, limit: 2, offset: 2)
    assert page1["total"] == 5 and length(page1["results"]) == 2
    assert page2["total"] == 5 and length(page2["results"]) == 2
    assert MapSet.disjoint?(MapSet.new(skus(page1)), MapSet.new(skus(page2)))
  end

  test "no results is an empty list, not an error", %{conn: conn} do
    assert %{"results" => [], "total" => 0, "match" => "none"} =
             search(conn, q: "#{tag()}nothing")
  end

  test "a missing or empty q, or a bad limit, is a 400", %{conn: conn} do
    assert conn |> get("/api/search/products") |> json_response(400)
    assert conn |> get("/api/search/products?q=") |> json_response(400)
    assert conn |> get("/api/search/products?q=%20%20") |> json_response(400)
    assert conn |> get("/api/search/products?q=tea&limit=0") |> json_response(400)
    assert conn |> get("/api/search/products?q=tea&limit=51") |> json_response(400)
    assert conn |> get("/api/search/products?q=tea&offset=1001") |> json_response(400)
    assert conn |> get("/api/search/products?q=tea&limit=abc") |> json_response(400)
  end

  test "whatever is typed is just words: no input makes a 500", %{conn: conn} do
    product_fixture(%{name: "Green tea"})

    for q <- [
          "&",
          "|",
          "!",
          "'",
          "\"",
          "\\",
          "(",
          ")",
          ":*",
          "tea & !",
          "<->",
          "' OR 1=1 --",
          String.duplicate("x", 500),
          "🍵"
        ] do
      assert conn |> get("/api/search/products?" <> URI.encode_query(q: q)) |> response(200),
             inspect(q)
    end
  end

  test "the snippet marks words with [[ ]], never with HTML tags of ours", %{conn: conn} do
    t = tag()

    product_fixture(%{name: "#{t} Tea", description: "great #{t} <script>alert(1)</script>"})
    [r] = search(conn, q: t)["results"]
    refute r["snippet"] =~ "<mark>"
    assert r["snippet"] =~ "[[#{t}]]"
  end

  describe "an admin's changes are searchable at once" do
    test "create, change, delete", %{conn: conn} do
      admin = log_in(conn, admin_fixture())
      t = tag()

      created =
        admin
        |> post("/api/products", %{
          "sku" => "S-#{t}",
          "name" => "#{t} Oolong",
          "description" => "Roasted",
          "price_cents" => 1800
        })
        |> json_response(201)

      assert created["sku"] == "S-#{t}" and created["description"] == "Roasted"
      assert ["S-" <> _] = skus(search(conn, q: "#{t} oolong"))

      admin
      |> put("/api/products/S-#{t}/details", %{"name" => "#{t} Jasmine"})
      |> json_response(200)

      assert skus(search(conn, q: "#{t} oolong")) |> Enum.reject(&(&1 == "S-#{t}")) == []
      assert "S-#{t}" in skus(search(conn, q: "#{t} jasmine"))

      assert %{"name" => name, "description" => "Roasted"} =
               conn |> get("/api/products/S-#{t}") |> json_response(200)

      assert name == "#{t} Jasmine"

      admin |> delete("/api/products/S-#{t}") |> response(204)
      assert search(conn, q: "#{t} jasmine", limit: 5)["match"] != "text"
      assert conn |> get("/api/products/S-#{t}") |> json_response(404)
    end

    test "only an admin, and bad input is refused", %{conn: conn} do
      customer = log_in(conn, user_fixture())
      admin = log_in(conn, admin_fixture())
      body = %{"sku" => "X-#{tag()}", "name" => "Nope", "price_cents" => 100}

      assert conn |> post("/api/products", body) |> json_response(401)
      assert customer |> post("/api/products", body) |> json_response(403)
      assert customer |> put("/api/products/ANY/details", %{"name" => "x"}) |> json_response(403)
      assert customer |> delete("/api/products/ANY") |> json_response(403)

      assert %{"errors" => %{"sku" => [_]}} =
               admin |> post("/api/products", %{body | "sku" => "bad sku!"}) |> json_response(422)

      assert %{"errors" => %{"name" => [_]}} =
               admin |> post("/api/products", %{body | "name" => ""}) |> json_response(422)

      assert %{"errors" => %{"price_cents" => [_]}} =
               admin
               |> post("/api/products", Map.put(body, "price_cents", -1))
               |> json_response(422)

      assert admin |> put("/api/products/NOPE/details", %{"name" => "x"}) |> json_response(404)
      assert admin |> delete("/api/products/NOPE") |> json_response(404)

      p = product_fixture()

      assert %{"errors" => _} =
               admin |> put("/api/products/#{p.sku}/details", %{}) |> json_response(422)
    end

    test "a duplicate sku is refused", %{conn: conn} do
      admin = log_in(conn, admin_fixture())
      p = product_fixture()

      assert %{"errors" => %{"sku" => [_]}} =
               admin
               |> post("/api/products", %{"sku" => p.sku, "name" => "Again", "price_cents" => 1})
               |> json_response(422)
    end
  end
end
