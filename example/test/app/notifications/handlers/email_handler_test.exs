defmodule App.Notifications.Handlers.EmailHandlerTest do
  use Platform.ConnCase, async: true

  import App.Accounts.Fixtures
  import App.Shop.Fixtures

  alias App.Notifications.Services.EmailService
  alias App.Shop.Workers.SendOrderConfirmation

  defp admin_conn(conn), do: log_in(conn, admin_fixture())

  defp emails(conn, query),
    do: conn |> get("/api/emails" <> query) |> json_response(200) |> Map.fetch!("emails")

  test "only an admin sees what was sent", %{conn: conn} do
    assert conn |> get("/api/emails") |> json_response(401)
    assert conn |> log_in(user_fixture()) |> get("/api/emails") |> json_response(403)
  end

  test "lists emails, newest first, a page at a time", %{conn: conn} do
    conn = admin_conn(conn)
    tag = System.unique_integer([:positive])

    for i <- 1..3 do
      :ok =
        EmailService.send_once("t#{tag}-#{i}", "test", "a#{i}@example.com", "Hello #{i}", "body")
    end

    [newest | _] = page = emails(conn, "?limit=3")
    assert Enum.map(page, & &1["subject"]) == ["Hello 3", "Hello 2", "Hello 1"]

    assert %{"to" => "a3@example.com", "status" => "sent", "attempts" => 1, "kind" => "test"} =
             newest

    refute Map.has_key?(newest, "body")

    older = emails(conn, "?limit=2&before=#{newest["id"]}")
    assert Enum.map(older, & &1["subject"]) == ["Hello 2", "Hello 1"]
  end

  test "a status filters; none of these failed", %{conn: conn} do
    conn = admin_conn(conn)

    :ok =
      EmailService.send_once(
        "s#{System.unique_integer([:positive])}",
        "test",
        "x@example.com",
        "Hello",
        "body"
      )

    failed = emails(conn, "?status=failed&limit=200")
    assert Enum.all?(failed, &(&1["status"] == "failed"))
    assert Enum.all?(emails(conn, "?status=sent&limit=200"), &(&1["status"] == "sent"))
  end

  test "a bad status or page parameter is a 400", %{conn: conn} do
    conn = admin_conn(conn)
    assert conn |> get("/api/emails?status=lost") |> json_response(400)
    assert conn |> get("/api/emails?limit=0") |> json_response(400)
    assert conn |> get("/api/emails?before=x") |> json_response(400)
  end

  test "the confirmation for an order shows up as sent", %{conn: conn} do
    order = order_fixture()

    assert :ok =
             SendOrderConfirmation.perform(%Oban.Job{
               args: %{"payload" => %{"order_id" => order.id}}
             })

    assert conn
           |> admin_conn()
           |> emails("?limit=50")
           |> Enum.any?(&(&1["subject"] == "Your order ##{order.id}" and &1["status"] == "sent"))
  end
end
