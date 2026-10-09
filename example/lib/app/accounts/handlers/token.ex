defmodule App.Accounts.Handlers.Token do
  @moduledoc """
  The login token: a signed, time-limited string that says "this is user 42".
  ≈ a signed JWT in a Go service — and, like one, nothing is stored: any node
  can check it, because all nodes share the same `secret_key_base`.

  It is made with `Phoenix.Token` (HMAC-signed, expires after one day). Two
  limits to know about:

    * **It can't be revoked one by one** before it expires. A user who is deleted or demoted
      is caught anyway, because every request loads the user again, and **a password change
      ends every token made before it** (a fingerprint of the password hash is inside the
      token); but a stolen token is good for up to a day unless the password changes. For
      revoking one session, keep a token id in the database and check it, or shorten
      `:token_max_age`.
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
  def sign(%User{id: id, password_hash: hash}),
    do: Phoenix.Token.sign(Endpoint, @salt, {id, fingerprint(hash)})

  @doc "The user a token belongs to, if the token is genuine and not expired."
  @spec verify(term()) :: {:ok, User.t()} | {:error, :unauthorized}
  def verify(token) when is_binary(token) do
    with {:ok, {id, fingerprint}} <-
           Phoenix.Token.verify(Endpoint, @salt, token, max_age: max_age()),
         {:ok, user} <- UserService.get(id),
         true <- fingerprint == fingerprint(user.password_hash) do
      {:ok, user}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def verify(_token), do: {:error, :unauthorized}

  # A token says which password it was made under (a hash of the hash, cut short): change the
  # password and every token made before stops working, on every node, with nothing stored.
  defp fingerprint(password_hash),
    do:
      :sha256
      |> :crypto.hash(password_hash)
      |> binary_part(0, 8)
      |> Base.url_encode64(padding: false)

  defp max_age, do: Application.get_env(:acme, __MODULE__, [])[:max_age] || @default_max_age
end
