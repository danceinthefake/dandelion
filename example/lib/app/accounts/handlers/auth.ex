defmodule App.Accounts.Handlers.Auth do
  @moduledoc """
  Plugs that guard routes. ≈ a Go `func Auth(next http.Handler) http.Handler`
  middleware. The router lists them as pipelines, so each route says what it
  needs:

      pipeline :authenticated do
        plug App.Accounts.Handlers.Auth, :authenticate
      end

      pipeline :admin do
        plug App.Accounts.Handlers.Auth, :require_admin
      end

  `:authenticate` reads `Authorization: Bearer <token>` and puts the user in
  `conn.assigns.current_user`, or answers 401 and stops. `:require_admin` goes
  after it and answers 403 to anyone who isn't an admin.

  A handler never needs to check who is calling — except to decide *what they
  may see*: that is a rule, so it lives in the service (`OrderService` shows a
  customer only their own orders), not here.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias App.Accounts.Handlers.Token
  alias App.Accounts.Services.UserService

  def init(action) when action in [:authenticate, :require_admin], do: action

  def call(conn, :authenticate) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Token.verify(token) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_resp_header("www-authenticate", "Bearer")
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
        |> halt()
    end
  end

  def call(conn, :require_admin) do
    if UserService.admin?(conn.assigns.current_user) do
      conn
    else
      conn |> put_status(:forbidden) |> json(%{error: "forbidden"}) |> halt()
    end
  end
end
