defmodule App.Accounts.Handlers.Token do
  @moduledoc """
  The login token: a signed, time-limited string that says "this is user 42".
  ≈ a signed JWT in a Go service — and, like one, nothing is stored: any node
  can check it, because all nodes share the same `secret_key_base`.

  It is made with `Phoenix.Token` (HMAC-signed, expires after one day). Two
  limits to know about:

    * **It can't be revoked** before it expires. A user who is deleted or demoted
      is caught anyway, because every request loads the user again; a stolen
      token is good for up to a day. For revocation, keep a token id in the
      database and check it (that's a session), or shorten `:token_max_age`.
    * It travels in an `Authorization: Bearer …` header, so keep it out of URLs
      and logs. The web UI keeps it in `sessionStorage`; if you serve HTML pages
      instead, use an `HttpOnly` cookie and CSRF protection.

  Set the lifetime in seconds with `config :acme, App.Accounts.Handlers.Token,
  max_age: 3600`.
  """
  alias App.Accounts.Models.User
  alias App.Accounts.Services.UserService
  alias Platform.Web.Endpoint

  @salt "user token"
  @default_max_age 86_400

  @doc "A token for this user."
  @spec sign(User.t()) :: String.t()
  def sign(%User{id: id}), do: Phoenix.Token.sign(Endpoint, @salt, id)

  @doc "The user a token belongs to, if the token is genuine and not expired."
  @spec verify(term()) :: {:ok, User.t()} | {:error, :unauthorized}
  def verify(token) when is_binary(token) do
    with {:ok, id} <- Phoenix.Token.verify(Endpoint, @salt, token, max_age: max_age()),
         {:ok, user} <- UserService.get(id) do
      {:ok, user}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def verify(_token), do: {:error, :unauthorized}

  defp max_age, do: Application.get_env(:acme, __MODULE__, [])[:max_age] || @default_max_age
end
