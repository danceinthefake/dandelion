defmodule App.Accounts.Services.Password do
  @moduledoc """
  Password hashing with PBKDF2-SHA256, from Erlang's `:crypto` — no dependency.
  ≈ `golang.org/x/crypto/pbkdf2`, or bcrypt / argon2 in a Go service.

  A stored hash looks like `pbkdf2_sha256$600000$<salt>$<hash>`: it carries its
  own salt and iteration count, so the count can be raised later and old hashes
  still check.

  The iteration count is OWASP's 2023 figure for PBKDF2-SHA256 (600 000, about a
  quarter of a second). If you can add a dependency, `argon2_elixir` or
  `bcrypt_elixir` are stronger; this module is the one place to change.
  Tests use a few thousand iterations (`config/test.exs`).
  """
  @prefix "pbkdf2_sha256"
  @default_iterations 600_000

  @doc "Hashes a password with a fresh random salt."
  @spec hash(String.t()) :: String.t()
  def hash(password) do
    salt = :crypto.strong_rand_bytes(16)
    iterations = iterations()
    Enum.join([@prefix, iterations, b64(salt), b64(derive(password, salt, iterations))], "$")
  end

  @doc "Does `password` match the stored hash? Constant time in the comparison."
  @spec verify(String.t(), String.t()) :: boolean()
  def verify(password, stored) do
    with [@prefix, iterations, salt, hash] <- String.split(stored, "$"),
         {iterations, ""} <- Integer.parse(iterations),
         {:ok, salt} <- Base.decode64(salt, padding: false),
         {:ok, hash} <- Base.decode64(hash, padding: false) do
      Plug.Crypto.secure_compare(derive(password, salt, iterations), hash)
    else
      _ -> false
    end
  end

  @doc """
  Does the same work as `verify/2` against nothing, so that logging in as an
  email that doesn't exist takes as long as one that does (otherwise the
  response time tells an attacker which emails have accounts).
  """
  def verify_nothing do
    derive("x", "0123456789abcdef", iterations())
    false
  end

  defp derive(password, salt, iterations),
    do: :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, 32)

  defp b64(binary), do: Base.encode64(binary, padding: false)

  defp iterations,
    do: Application.get_env(:acme, __MODULE__, [])[:iterations] || @default_iterations
end
