defmodule ShopWeb.Handlers.HealthHandlerTest do
  use ShopWeb.ConnCase, async: true

  test "GET /health is 200 while the database answers", %{conn: conn} do
    assert conn |> get("/health") |> json_response(200) == %{"status" => "ok"}
  end
end
