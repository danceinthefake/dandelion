defmodule App.Accounts.Settings do
  @moduledoc """
  The numbers of the accounts domain, from `config :acme, App.Accounts` (`config/config.exs`,
  and `config/runtime.exs` for the environment).
  """

  @doc "Consecutive wrong passwords for one address before it is locked."
  def login_max_failures, do: get(:login_max_failures)

  @doc "How long a locked address stays locked, in seconds."
  def lockout_seconds, do: get(:lockout_seconds)

  @doc "How long a password reset link works, in seconds."
  def reset_ttl_seconds, do: get(:reset_ttl_seconds)

  @doc "How long an address confirmation link works, in seconds."
  def confirm_ttl_seconds, do: get(:confirm_ttl_seconds)

  @doc "The shortest time between two emails of the same kind to the same user, in seconds."
  def resend_gap_seconds, do: get(:resend_gap_seconds)

  @doc "Whether an order needs a confirmed email address."
  def require_confirmed_email?, do: get(:require_confirmed_email)

  defp get(key), do: Application.fetch_env!(:acme, App.Accounts) |> Keyword.fetch!(key)
end
