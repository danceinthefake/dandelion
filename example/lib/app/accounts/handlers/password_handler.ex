defmodule App.Accounts.Handlers.PasswordHandler do
  @moduledoc """
  A forgotten password: ask for a link, use the link. ≈ `http/password.go`. Neither route needs a
  login. Asking answers 202 whether or not there is an account for the address.
  """
  use Platform.Web, :handler

  alias App.Accounts.Services.AccountService

  action_fallback Platform.Web.FallbackHandler

  # POST /api/password/forgot   {"email": "sari@example.com"}
  def forgot(conn, params) do
    :ok = AccountService.request_password_reset(params["email"])

    conn
    |> put_status(:accepted)
    |> json(%{status: "if there is an account for that address, an email is on its way"})
  end

  # POST /api/password/reset   {"token": "…", "password": "a new one, 10 characters or more"}
  def reset(conn, %{"token" => token, "password" => password}) do
    with {:ok, _user} <- AccountService.reset_password(token, password),
         do: json(conn, %{status: "ok"})
  end

  def reset(_conn, _params), do: {:error, {:invalid, "send a token and a password"}}
end
