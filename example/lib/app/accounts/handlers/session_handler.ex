defmodule App.Accounts.Handlers.SessionHandler do
  @moduledoc """
  Logging in, and "who am I". ≈ `http/session.go`.
  """
  use Platform.Web, :handler

  alias App.Accounts.Handlers.{Token, UserJSON}
  alias App.Accounts.Services.UserService

  # POST /api/session   {"email": "…", "password": "…"}  →  {"token": "…", "user": {…}}
  def create(conn, params) do
    case UserService.authenticate(params["email"], params["password"]) do
      {:ok, user} ->
        json(conn, %{token: Token.sign(user), user: UserJSON.user(user)})

      # the same answer for an unknown email and a wrong password
      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid email or password"})
    end
  end

  # GET /api/me   (needs a token)
  def show(conn, _params), do: json(conn, UserJSON.user(conn.assigns.current_user))
end
