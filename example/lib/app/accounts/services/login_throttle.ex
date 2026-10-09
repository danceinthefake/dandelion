defmodule App.Accounts.Services.LoginThrottle do
  @moduledoc """
  Locking an address after too many wrong passwords. ≈ the "5 failed attempts" rule of a bank
  login — in Postgres, so it counts the same whichever node the guesses reach and survives
  restarts. (`Platform.Web.RateLimit` slows a *client* down, per node, in memory; this protects
  an *account*, whoever is guessing and from wherever.)

  It is keyed by the address as typed (trimmed, lower case), **whether or not an account has that
  address**: guessing at an unknown address is locked in the same way, so a lock does not tell an
  attacker which addresses have accounts.

    * `check/1` — before looking at the password: `{:locked, seconds}` or `:ok`. A locked address
      is refused even with the right password (or the guesser would simply keep guessing).
    * `failure/1` — a wrong password. Counted under a row lock, so simultaneous guesses on several
      nodes are counted exactly. The `max`-th in a row locks the address for `lockout` seconds; once
      that has passed, the count starts again.
    * `success/1` and `clear/1` — a right password, or a password reset, forget the failures.

  The cost of this is the usual one: someone who knows your address can lock you out for 15
  minutes by guessing wrong. A password reset (an email to you) unlocks it.
  """
  alias App.Accounts.Settings
  alias Platform.Database.Repo

  @max_email 200

  @spec normalize(term()) :: String.t()
  def normalize(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase() |> String.slice(0, @max_email)

  def normalize(_other), do: "-"

  @spec check(String.t()) :: :ok | {:locked, pos_integer()}
  def check(email) do
    case Repo.query!("SELECT locked_until FROM login_throttle WHERE email = $1", [email]) do
      %{rows: [[locked_until]]} when not is_nil(locked_until) ->
        left = NaiveDateTime.diff(locked_until, NaiveDateTime.utc_now(), :second)
        if left > 0, do: {:locked, left}, else: :ok

      _ ->
        :ok
    end
  end

  @doc "Counts a wrong password. Returns whether this one locked the address."
  @spec failure(String.t()) :: %{locked?: boolean(), failures: pos_integer()}
  def failure(email) do
    now = NaiveDateTime.utc_now()

    {:ok, result} =
      Repo.transact(fn ->
        Repo.query!(
          "INSERT INTO login_throttle (email, failures, updated_at) VALUES ($1, 0, $2) ON CONFLICT (email) DO NOTHING",
          [email, now]
        )

        %{rows: [[failures, locked_until]]} =
          Repo.query!(
            "SELECT failures, locked_until FROM login_throttle WHERE email = $1 FOR UPDATE",
            [email]
          )

        # a lock that has run out: start counting again
        failures =
          if locked_until && NaiveDateTime.compare(locked_until, now) != :gt,
            do: 0,
            else: failures

        locked_until =
          if locked_until && NaiveDateTime.compare(locked_until, now) == :gt, do: locked_until

        failures = failures + 1
        newly_locked? = is_nil(locked_until) and failures >= Settings.login_max_failures()

        locked_until =
          if newly_locked?,
            do: NaiveDateTime.add(now, Settings.lockout_seconds(), :second),
            else: locked_until

        Repo.query!(
          "UPDATE login_throttle SET failures = $2, locked_until = $3, updated_at = $4 WHERE email = $1",
          [email, failures, locked_until, now]
        )

        {:ok, %{locked?: newly_locked?, failures: failures}}
      end)

    result
  end

  @spec success(String.t()) :: :ok
  def success(email), do: clear(email)

  @spec clear(String.t()) :: :ok
  def clear(email) do
    Repo.query!("DELETE FROM login_throttle WHERE email = $1", [email])
    :ok
  end

  @doc "Removes rows that are not locked and have not been touched for a day. Returns how many."
  @spec prune() :: non_neg_integer()
  def prune do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -86_400, :second)

    %{num_rows: n} =
      Repo.query!(
        "DELETE FROM login_throttle WHERE updated_at < $1 AND (locked_until IS NULL OR locked_until < $1)",
        [cutoff]
      )

    n
  end
end
