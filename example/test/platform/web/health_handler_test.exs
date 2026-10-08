defmodule Platform.Web.HealthHandlerTest do
  use Platform.ConnCase, async: false

  test "GET /health is 200 while the database answers", %{conn: conn} do
    assert conn |> get("/health") |> json_response(200) == %{"status" => "ok"}
  end

  test "a node that was told to stop says so, so the load balancer moves away", %{conn: conn} do
    Dandelion.Drain.start(0)
    on_exit(&Dandelion.Drain.reset/0)

    assert conn |> get("/health") |> json_response(503) == %{"status" => "draining"}
  end

  test "a database that can't be reached is a 503 (not a crash, not a 500)" do
    error = %DBConnection.ConnectionError{message: "connection not available", severity: :error}
    assert Plug.Exception.status(error) == 503
    assert Plug.Exception.actions(error) == []
  end

  test "a statement the database cancelled (our timeout) is a 503, other database errors a 500" do
    cancelled = %Postgrex.Error{
      postgres: %{code: :query_canceled, message: "canceling statement"}
    }

    assert Plug.Exception.status(cancelled) == 503

    other = %Postgrex.Error{postgres: %{code: :unique_violation, message: "duplicate"}}
    assert Plug.Exception.status(other) == 500
  end

  test "a database error that is not a connection problem stays a 500" do
    assert Plug.Exception.status(%RuntimeError{message: "boom"}) == 500
  end
end
