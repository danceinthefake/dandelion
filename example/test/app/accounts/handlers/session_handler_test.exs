defmodule App.Accounts.Handlers.SessionHandlerTest do
  use Platform.ConnCase, async: true

  import App.Accounts.Fixtures

  alias App.Accounts.Handlers.Token
  alias Platform.Database.Repo

  describe "POST /api/users" do
    test "registers a customer and never returns the password", %{conn: conn} do
      params = %{"email" => "new@example.com", "password" => password(), "role" => "admin"}
      body = conn |> post("/api/users", params) |> json_response(201)

      assert %{"id" => _, "email" => "new@example.com", "role" => "customer"} = body
      refute inspect(body) =~ password()
      refute Map.has_key?(body, "password_hash")
    end

    test "invalid input is 422 with field errors; a taken email too", %{conn: conn} do
      assert %{"errors" => %{"email" => _, "password" => _}} =
               conn |> post("/api/users", %{}) |> json_response(422)

      user = user_fixture()

      assert %{"errors" => %{"email" => ["has already been taken"]}} =
               conn
               |> post("/api/users", %{"email" => user.email, "password" => password()})
               |> json_response(422)
    end
  end

  describe "POST /api/session" do
    test "logs in with the right credentials: a token that works", %{conn: conn} do
      user = user_fixture()

      body =
        conn
        |> post("/api/session", %{"email" => user.email, "password" => password()})
        |> json_response(200)

      assert %{"token" => token, "user" => %{"email" => email, "role" => "customer"}} = body
      assert email == user.email
      assert {:ok, %{id: id}} = Token.verify(token)
      assert id == user.id

      me = build_conn() |> put_req_header("authorization", "Bearer " <> token) |> get("/api/me")
      assert %{"email" => ^email} = json_response(me, 200)
    end

    test "a wrong password and an unknown email look the same: 401", %{conn: conn} do
      user = user_fixture()

      a = conn |> post("/api/session", %{"email" => user.email, "password" => "wrong password"})

      b =
        build_conn()
        |> post("/api/session", %{"email" => "nobody@example.com", "password" => "x"})

      assert json_response(a, 401) == json_response(b, 401)
      assert %{"error" => "invalid email or password"} = json_response(a, 401)
    end

    test "missing fields are 401, not a crash", %{conn: conn} do
      assert conn |> post("/api/session", %{}) |> json_response(401)
      assert build_conn() |> post("/api/session", %{"email" => %{"a" => 1}}) |> json_response(401)
    end
  end

  describe "the Authenticate plug (GET /api/me)" do
    test "no token, a malformed header, a bad token: all 401 with a challenge", %{conn: conn} do
      for header <- [nil, "Bearer", "Bearer nope", "Basic abc", "bearer lower"] do
        c = if header, do: put_req_header(conn, "authorization", header), else: conn
        c = get(c, "/api/me")
        assert %{"error" => "unauthorized"} = json_response(c, 401)
        assert get_resp_header(c, "www-authenticate") == ["Bearer"]
      end
    end

    test "a token signed with another secret is refused", %{conn: conn} do
      user = user_fixture()

      forged =
        Phoenix.Token.sign(
          "another-secret-another-secret-another-secret-0000",
          "user token",
          user.id
        )

      assert conn
             |> put_req_header("authorization", "Bearer " <> forged)
             |> get("/api/me")
             |> json_response(401)
    end

    test "a tampered token is refused", %{conn: conn} do
      token = Token.sign(user_fixture())
      tampered = String.slice(token, 0..-3//1) <> "xx"

      assert conn
             |> put_req_header("authorization", "Bearer " <> tampered)
             |> get("/api/me")
             |> json_response(401)
    end

    test "an expired token is refused", %{conn: conn} do
      user = user_fixture()
      old = Phoenix.Token.sign(Platform.Web.Endpoint, "user token", user.id, signed_at: 0)

      assert conn
             |> put_req_header("authorization", "Bearer " <> old)
             |> get("/api/me")
             |> json_response(401)
    end

    test "a token for a user who is gone is refused", %{conn: conn} do
      user = user_fixture()
      token = Token.sign(user)
      Repo.delete!(user)

      assert conn
             |> put_req_header("authorization", "Bearer " <> token)
             |> get("/api/me")
             |> json_response(401)
    end

    test "a token for another purpose (another salt) is refused", %{conn: conn} do
      user = user_fixture()
      other = Phoenix.Token.sign(Platform.Web.Endpoint, "something else", user.id)

      assert conn
             |> put_req_header("authorization", "Bearer " <> other)
             |> get("/api/me")
             |> json_response(401)
    end
  end
end
