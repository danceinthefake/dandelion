defmodule App.Accounts.Handlers.SessionHandler do
  @moduledoc """
  Logging in, and "who am I". ≈ `http/session.go`.
  """
  use Platform.Web, :handler

  alias App.Accounts.Handlers.{Token, UserJSON}
  alias App.Accounts.Services.UserService
  alias App.Audit.Services.AuditService

  # POST /api/session   {"email": "…", "password": "…"}  →  {"token": "…", "user": {…}}
  def create(conn, params) do
    case UserService.authenticate(params["email"], params["password"]) do
      {:ok, user} ->
        AuditService.record("user:#{user.id}", "session.created", "user:#{user.id}")
        json(conn, %{token: Token.sign(user), user: UserJSON.user(user)})

      # the same answer for an unknown email and a wrong password
      {:error, :unauthorized} ->
        AuditService.record(
          "anonymous",
          "session.rejected",
          "email:#{attempted(params["email"])}"
        )

        conn |> put_status(:unauthorized) |> json(%{error: "invalid email or password"})
    end
  end

  # what was typed, for the log: text only, short, lower case (it is not a user we know)
  defp attempted(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase() |> String.slice(0, 100)

  defp attempted(_), do: "-"

  # GET /api/me   (needs a token)
  def show(conn, _params), do: json(conn, UserJSON.user(conn.assigns.current_user))
end
