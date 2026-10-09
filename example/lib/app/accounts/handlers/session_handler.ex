defmodule App.Accounts.Handlers.SessionHandler do
  @moduledoc """
  Logging in, and "who am I". ≈ `http/session.go`.

  Logging in is protected two ways: `Platform.Web.RateLimit` slows a client down, and
  `App.Accounts.Services.LoginThrottle` locks an *address* after too many wrong passwords, from
  wherever they come.
  """
  use Platform.Web, :handler

  alias App.Accounts.Handlers.{Token, UserJSON}
  alias App.Accounts.Services.{LoginThrottle, UserService}
  alias App.Audit.Services.AuditService

  # POST /api/session   {"email": "…", "password": "…"}  →  {"token": "…", "user": {…}}
  def create(conn, params) do
    email = LoginThrottle.normalize(params["email"])

    case LoginThrottle.check(email) do
      # too many wrong passwords for this address: nothing is checked, not even a right one
      {:locked, seconds} ->
        conn
        |> put_resp_header("retry-after", to_string(seconds))
        |> put_status(:too_many_requests)
        |> json(%{
          error:
            "too many wrong passwords for this address: try again later, or reset the password"
        })

      :ok ->
        attempt(conn, params, email)
    end
  end

  defp attempt(conn, params, email) do
    case UserService.authenticate(params["email"], params["password"]) do
      {:ok, user} ->
        LoginThrottle.success(email)
        AuditService.record("user:#{user.id}", "session.created", "user:#{user.id}")
        json(conn, %{token: Token.sign(user), user: UserJSON.user(user)})

      # the same answer for an unknown email and a wrong password
      {:error, :unauthorized} ->
        %{locked?: locked?} = LoginThrottle.failure(email)
        AuditService.record("anonymous", "session.rejected", "email:#{email}")
        if locked?, do: AuditService.record("anonymous", "session.locked", "email:#{email}")
        conn |> put_status(:unauthorized) |> json(%{error: "invalid email or password"})
    end
  end

  # GET /api/me   (needs a token)
  def show(conn, _params), do: json(conn, UserJSON.user(conn.assigns.current_user))
end
