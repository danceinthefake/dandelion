defmodule App.Accounts.Handlers.AccountSecurityTest do
  # (it changes the settings of the accounts domain, which every test reads)
  use Platform.ConnCase, async: false
  use Oban.Testing, repo: Platform.Database.Repo

  import App.Accounts.Fixtures
  import App.Shop.Fixtures

  alias App.Accounts.Handlers.Token
  alias App.Accounts.Models.User
  alias App.Accounts.Workers.SendAccountEmail
  alias Platform.Database.Repos.UserRepo

  @new_password "a brand new password"

  defp forgot(conn, email), do: post(conn, "/api/password/forgot", %{"email" => email})

  defp reset(conn, secret, password),
    do: post(conn, "/api/password/reset", %{"token" => secret, "password" => password})

  defp login(conn, email, password),
    do: post(conn, "/api/session", %{"email" => email, "password" => password})

  describe "a forgotten password" do
    test "asking is the same answer for an address with an account and one without", %{conn: conn} do
      user = user_fixture()
      known = conn |> forgot(user.email) |> json_response(202)

      unknown =
        conn
        |> forgot("nobody-#{System.unique_integer([:positive])}@example.com")
        |> json_response(202)

      assert known == unknown

      # but only one of them has an email on its way
      assert [%{args: %{"user_id" => id, "kind" => "reset"}}] =
               all_enqueued(worker: SendAccountEmail)

      assert id == user.id
    end

    test "a link sets a new password; the old one stops working", %{conn: conn} do
      user = user_fixture()
      conn |> forgot(user.email) |> json_response(202)
      secret = email_secret(user, "reset")

      assert %{"status" => "ok"} = conn |> reset(secret, @new_password) |> json_response(200)
      assert conn |> login(user.email, password()) |> json_response(401)
      assert %{"token" => _} = conn |> login(user.email, @new_password) |> json_response(200)
    end

    test "the link works once", %{conn: conn} do
      user = user_fixture()
      conn |> forgot(user.email) |> json_response(202)
      secret = email_secret(user, "reset")

      conn |> reset(secret, @new_password) |> json_response(200)

      assert %{"error" => message} =
               conn |> reset(secret, "yet another password") |> json_response(400)

      assert message =~ "not valid"
    end

    test "a wrong, mangled or missing link is the same 400", %{conn: conn} do
      for secret <- ["nope", "", String.duplicate("a", 300)] do
        assert conn |> reset(secret, @new_password) |> json_response(400)
      end

      assert conn
             |> post("/api/password/reset", %{"password" => @new_password})
             |> json_response(400)
    end

    test "a password that is too short is refused, and the link is not used up", %{conn: conn} do
      user = user_fixture()
      conn |> forgot(user.email) |> json_response(202)
      secret = email_secret(user, "reset")

      assert %{"errors" => %{"password" => [_]}} =
               conn |> reset(secret, "short") |> json_response(422)

      assert conn |> reset(secret, @new_password) |> json_response(200)
    end

    test "every session the old password had ends", %{conn: conn} do
      user = user_fixture()
      old_token = Token.sign(user)
      assert {:ok, _} = Token.verify(old_token)

      conn |> forgot(user.email) |> json_response(202)
      conn |> reset(email_secret(user, "reset"), @new_password) |> json_response(200)

      assert {:error, :unauthorized} = Token.verify(old_token)

      assert conn
             |> put_req_header("authorization", "Bearer " <> old_token)
             |> get("/api/me")
             |> json_response(401)

      %{"token" => fresh} = conn |> login(user.email, @new_password) |> json_response(200)

      assert conn
             |> put_req_header("authorization", "Bearer " <> fresh)
             |> get("/api/me")
             |> json_response(200)
    end

    test "using the link also confirms the address, and unlocks it", %{conn: conn} do
      put_setting(:login_max_failures, 2)
      user = user_fixture()
      refute User.confirmed?(user)
      for _ <- 1..2, do: conn |> login(user.email, "wrong password 1") |> json_response(401)
      assert conn |> login(user.email, password()) |> json_response(429)

      conn |> forgot(user.email) |> json_response(202)
      conn |> reset(email_secret(user, "reset"), @new_password) |> json_response(200)

      assert User.confirmed?(UserRepo.get(user.id))
      assert conn |> login(user.email, @new_password) |> json_response(200)
    end

    test "asking again at once makes no second email", %{conn: conn} do
      user = user_fixture()
      conn |> forgot(user.email) |> json_response(202)
      conn |> forgot(user.email) |> json_response(202)
      assert [_] = all_enqueued(worker: SendAccountEmail)

      # and once a link was made, the gap holds even after the job has run
      email_secret(user, "reset")
      conn |> forgot(user.email) |> json_response(202)
      assert [_] = all_enqueued(worker: SendAccountEmail)
    end
  end

  describe "a wrong password, again and again" do
    setup do
      put_setting(:login_max_failures, 3)
      put_setting(:lockout_seconds, 600)
    end

    test "the address is locked, even for the right password; the answer says when", %{conn: conn} do
      user = user_fixture()

      for _ <- 1..3,
          do: assert(conn |> login(user.email, "wrong password 1") |> json_response(401))

      locked = login(conn, user.email, password())
      assert json_response(locked, 429)["error"] =~ "too many wrong passwords"
      assert [seconds] = get_resp_header(locked, "retry-after")
      assert String.to_integer(seconds) in 590..600
    end

    test "an address nobody has behaves the same, so a lock tells nothing", %{conn: conn} do
      ghost = "ghost-#{System.unique_integer([:positive])}@example.com"
      for _ <- 1..3, do: assert(conn |> login(ghost, "wrong password 1") |> json_response(401))
      assert conn |> login(ghost, "wrong password 1") |> json_response(429)
    end

    test "the case and spaces of the address do not get round it", %{conn: conn} do
      user = user_fixture()
      for _ <- 1..3, do: conn |> login(user.email, "wrong password 1") |> json_response(401)
      assert conn |> login("  " <> String.upcase(user.email), password()) |> json_response(429)
    end

    test "a right password in time forgets the wrong ones", %{conn: conn} do
      user = user_fixture()
      for _ <- 1..2, do: conn |> login(user.email, "wrong password 1") |> json_response(401)
      assert conn |> login(user.email, password()) |> json_response(200)
      for _ <- 1..2, do: conn |> login(user.email, "wrong password 1") |> json_response(401)
      assert conn |> login(user.email, password()) |> json_response(200)
    end

    test "locking is written in the audit log", %{conn: conn} do
      user = user_fixture()
      for _ <- 1..3, do: conn |> login(user.email, "wrong password 1") |> json_response(401)

      admin = log_in(Phoenix.ConnTest.build_conn(), admin_fixture())

      entries =
        admin
        |> get("/api/audit?action=session.locked&limit=5")
        |> json_response(200)
        |> Map.fetch!("entries")

      assert Enum.any?(entries, &(&1["subject"] == "email:#{user.email}"))
    end

    test "other addresses are not slowed down", %{conn: conn} do
      user = user_fixture()
      other = user_fixture()
      for _ <- 1..3, do: conn |> login(user.email, "wrong password 1") |> json_response(401)
      assert conn |> login(other.email, password()) |> json_response(200)
    end
  end

  describe "confirming an address" do
    test "registering sends a link; using it confirms, once", %{conn: conn} do
      email = "new-#{System.unique_integer([:positive])}@example.com"

      conn
      |> post("/api/users", %{"email" => email, "password" => "correct horse battery"})
      |> json_response(201)

      user = UserRepo.get_by_email(email)
      refute User.confirmed?(user)
      secret = email_secret(user, "confirm")

      assert %{"email_confirmed" => true} =
               conn |> post("/api/email/confirm", %{"token" => secret}) |> json_response(200)

      assert User.confirmed?(UserRepo.get(user.id))
      assert conn |> post("/api/email/confirm", %{"token" => secret}) |> json_response(400)
      assert conn |> post("/api/email/confirm", %{}) |> json_response(400)
    end

    test "me says whether it is confirmed; resending is for those who are not", %{conn: conn} do
      user = user_fixture()
      authed = log_in(conn, user)
      assert %{"email_confirmed" => false} = authed |> get("/api/me") |> json_response(200)

      assert authed |> post("/api/email/resend") |> json_response(202)
      secret = email_secret(user, "confirm")
      conn |> post("/api/email/confirm", %{"token" => secret}) |> json_response(200)

      assert %{"email_confirmed" => true} = authed |> get("/api/me") |> json_response(200)
      assert %{"error" => message} = authed |> post("/api/email/resend") |> json_response(409)
      assert message =~ "already confirmed"
      assert conn |> post("/api/email/resend") |> json_response(401)
    end

    test "an order needs a confirmed address only if that is asked for", %{conn: conn} do
      user = user_fixture()
      authed = log_in(conn, user)

      assert authed |> post("/api/orders", order_params()) |> json_response(201)

      put_setting(:require_confirmed_email, true)

      assert %{"error" => message} =
               authed |> post("/api/orders", order_params()) |> json_response(403)

      assert message =~ "confirm your email"

      UserRepo.confirm_email(user)
      assert authed |> post("/api/orders", order_params()) |> json_response(201)
    end
  end
end
