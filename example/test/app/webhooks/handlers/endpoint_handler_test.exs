defmodule App.Webhooks.Handlers.EndpointHandlerTest do
  use Platform.ConnCase, async: true

  import App.Accounts.Fixtures
  import App.Webhooks.Fixtures

  defp admin_conn(conn), do: log_in(conn, admin_fixture())

  test "only an admin manages webhooks", %{conn: conn} do
    assert conn |> get("/api/webhooks") |> json_response(401)
    assert conn |> log_in(user_fixture()) |> get("/api/webhooks") |> json_response(403)
  end

  test "creating one shows the secret, once", %{conn: conn} do
    conn = admin_conn(conn)

    created =
      conn
      |> post("/api/webhooks", %{
        "url" => "https://hooks.example.com/a",
        "events" => ["order.created"]
      })
      |> json_response(201)

    assert %{"id" => id, "secret" => "whsec_" <> _, "active" => true} = created

    assert %{"endpoints" => endpoints} = conn |> get("/api/webhooks") |> json_response(200)
    listed = Enum.find(endpoints, &(&1["id"] == id))
    assert listed["url"] == "https://hooks.example.com/a"
    refute Map.has_key?(listed, "secret")
  end

  test "bad input is a 422 with the field", %{conn: conn} do
    conn = admin_conn(conn)

    body =
      conn
      |> post("/api/webhooks", %{"url" => "https://hooks.example.com", "events" => ["nope"]})
      |> json_response(422)

    assert %{"errors" => %{"events" => [_]}} = body
  end

  test "deleting one removes it; an unknown id is 404", %{conn: conn} do
    conn = admin_conn(conn)
    endpoint = endpoint_fixture()
    assert conn |> delete("/api/webhooks/#{endpoint.id}") |> response(204)
    assert conn |> delete("/api/webhooks/#{endpoint.id}") |> json_response(404)
    assert conn |> delete("/api/webhooks/abc") |> json_response(404)
  end
end
