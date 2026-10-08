defmodule App.Audit.Handlers.AuditHandlerTest do
  use Platform.ConnCase, async: false

  import App.Accounts.Fixtures
  import App.Files.Fixtures
  import App.Shop.Fixtures

  alias App.Shop.Services.OrderService
  alias App.Webhooks.Services.EndpointService
  alias Dandelion.Cache

  setup %{conn: conn} do
    admin = admin_fixture()
    clean_uploads()
    on_exit(fn -> Cache.delete({:flag, "orders.enabled"}) end)
    {:ok, admin: admin, admin_conn: log_in(conn, admin), conn: conn}
  end

  defp entries(conn, query \\ "") do
    conn |> get("/api/audit" <> query) |> json_response(200) |> Map.fetch!("entries")
  end

  defp by(entries, action), do: Enum.filter(entries, &(&1["action"] == action))

  test "only an admin reads the log", %{conn: conn} do
    assert conn |> get("/api/audit") |> json_response(401)
    assert conn |> log_in(user_fixture()) |> get("/api/audit") |> json_response(403)
  end

  test "an admin's changes are recorded with who, what and from/to", %{
    admin: admin,
    admin_conn: conn
  } do
    actor = "user:#{admin.id}"

    conn |> put("/api/flags/orders.enabled", %{"value" => false}) |> json_response(200)
    conn |> put("/api/flags/orders.enabled", %{"value" => true}) |> json_response(200)
    conn |> delete("/api/flags/orders.enabled") |> response(204)

    product = product_fixture(%{price_cents: 1500})
    conn |> put("/api/products/#{product.sku}", %{"price_cents" => 1700}) |> json_response(200)

    hook =
      conn
      |> post("/api/webhooks", %{
        "url" => "https://hooks.example.com/x",
        "events" => ["order.created"]
      })
      |> json_response(201)

    conn |> delete("/api/webhooks/#{hook["id"]}") |> response(204)

    log = entries(conn, "?actor=#{actor}&limit=100")

    assert [%{"details" => %{"value" => true}}, %{"details" => %{"value" => false}}] =
             by(log, "flag.set")

    assert [%{"subject" => "flag:orders.enabled"}] = by(log, "flag.deleted")

    assert [%{"subject" => subject, "details" => %{"from" => 1500, "to" => 1700}}] =
             by(log, "product.price_changed")

    assert subject == "product:#{product.sku}"
    assert [%{"details" => created}] = by(log, "webhook.created")
    assert created == %{"url" => "https://hooks.example.com/x", "events" => ["order.created"]}
    assert [%{"subject" => "webhook:" <> _}] = by(log, "webhook.deleted")

    # the secret is nowhere in the log
    refute log |> Jason.encode!() |> String.contains?(hook["secret"])
  end

  test "an order cancelled by its customer, and one moved by the payment provider", %{
    admin_conn: conn
  } do
    customer = user_fixture()
    order = order_fixture(user_id: customer.id)
    other = order_fixture(user_id: customer.id)

    log_in(Phoenix.ConnTest.build_conn(), customer)
    |> post("/api/orders/#{order.id}/cancel")
    |> json_response(200)

    {:ok, _} = OrderService.mark_paid(other.id)
    {:ok, _} = OrderService.mark_refunded(other.id)
    {:ok, _} = OrderService.mark_refunded(other.id)

    log = entries(conn, "?action=order.&limit=100")

    assert [%{"actor" => actor, "details" => %{"from" => "pending"}}] =
             by(log, "order.cancelled") |> Enum.filter(&(&1["subject"] == "order:#{order.id}"))

    assert actor == "user:#{customer.id}"

    assert [%{"actor" => "system:payment"}] =
             by(log, "order.paid") |> Enum.filter(&(&1["subject"] == "order:#{other.id}"))

    # the repeat of a refund changed nothing, so it is not a second entry
    assert [_] = by(log, "order.refunded") |> Enum.filter(&(&1["subject"] == "order:#{other.id}"))
  end

  test "something that did not happen is not recorded", %{admin_conn: conn} do
    shipped = order_fixture(status: "shipped")
    before = length(entries(conn, "?limit=200"))

    # refused: shipped, unknown, invalid
    assert {:error, _} = OrderService.cancel(shipped.id)
    assert {:error, :not_found} = OrderService.cancel(-1)
    conn |> put("/api/products/NOPE", %{"price_cents" => 100}) |> json_response(404)
    conn |> put("/api/flags/Bad Key", %{"value" => 1}) |> json_response(400)
    assert {:error, _} = EndpointService.create(%{"url" => "http://localhost", "events" => []})

    assert length(entries(conn, "?limit=200")) == before
  end

  test "expired orders are one entry with a count", %{admin_conn: conn} do
    old = DateTime.add(DateTime.utc_now(), -7200, :second)
    order_fixture(inserted_at: old)
    order_fixture(inserted_at: old)

    assert OrderService.expire_unpaid(3600) >= 2

    assert [%{"actor" => "system:expiry", "details" => %{"count" => count}}] =
             by(entries(conn, "?action=orders.expired"), "orders.expired") |> Enum.take(1)

    assert count >= 2

    # nothing to expire: nothing recorded
    before = length(entries(conn, "?action=orders.expired&limit=200"))
    OrderService.expire_unpaid(3600)
    assert length(entries(conn, "?action=orders.expired&limit=200")) == before
  end

  test "logging in, a wrong password, and registering", %{admin_conn: conn} do
    email = "audited-#{System.unique_integer([:positive])}@example.com"
    anon = Phoenix.ConnTest.build_conn()

    anon
    |> post("/api/users", %{"email" => email, "password" => "correct horse battery"})
    |> json_response(201)

    anon
    |> post("/api/session", %{"email" => email, "password" => "wrong password 1"})
    |> json_response(401)

    anon
    |> post("/api/session", %{
      "email" => " " <> String.upcase(email),
      "password" => "correct horse battery"
    })
    |> json_response(200)

    log = entries(conn, "?limit=100")

    assert %{"actor" => "user:" <> id} = log |> by("session.created") |> hd()

    assert [%{"details" => %{"role" => "customer"}}] =
             log |> by("user.registered") |> Enum.filter(&(&1["actor"] == "user:#{id}"))

    # the wrong password: a rejection by "anonymous", for the email as typed
    assert %{"actor" => "anonymous", "subject" => "email:" <> ^email} =
             log |> by("session.rejected") |> hd()

    # the password is not in it
    refute Jason.encode!(log) =~ "correct horse"
    refute Jason.encode!(log) =~ "wrong password"
  end

  test "deleting a file is recorded with whose it was", %{admin: admin, admin_conn: conn} do
    owner = user_fixture()

    created =
      log_in(Phoenix.ConnTest.build_conn(), owner)
      |> post("/api/files", %{"file" => upload(png(), "scan.png")})
      |> json_response(201)

    conn |> delete("/api/files/#{created["id"]}") |> response(204)

    assert [%{"actor" => actor, "details" => %{"filename" => "scan.png", "owner" => owner_id}}] =
             by(entries(conn, "?action=file.deleted"), "file.deleted") |> Enum.take(1)

    assert actor == "user:#{admin.id}" and owner_id == owner.id
  end

  test "filters and pages", %{admin_conn: conn} do
    for i <- 1..5,
        do: conn |> put("/api/flags/page.test#{i}", %{"value" => i}) |> json_response(200)

    page1 = conn |> get("/api/audit?action=flag.set&limit=2") |> json_response(200)
    assert [_, _] = page1["entries"]
    assert is_integer(page1["next_before"])

    page2 =
      conn
      |> get("/api/audit?action=flag.set&limit=2&before=#{page1["next_before"]}")
      |> json_response(200)

    assert [_, _] = page2["entries"]
    assert Enum.all?(page2["entries"], &(&1["id"] < page1["next_before"]))

    # the last page says so
    last = conn |> get("/api/audit?actor=nobody&limit=2") |> json_response(200)
    assert last == %{"entries" => [], "next_before" => nil}
  end

  test "a bad page parameter is a 400", %{admin_conn: conn} do
    assert conn |> get("/api/audit?before=abc") |> json_response(400)
    assert conn |> get("/api/audit?limit=0") |> json_response(400)
  end
end
