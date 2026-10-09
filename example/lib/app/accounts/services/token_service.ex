defmodule App.Accounts.Services.TokenService do
  @moduledoc """
  The one-time links in emails: "reset your password", "confirm this address".

  `issue/2` makes a secret (256 random bits), keeps **only its SHA-256** and returns the secret,
  once, to be put in the email: a copy of the table is not a set of working links, and the
  secret is nowhere else (see `App.Accounts.Workers.SendAccountEmail`: it is written into the
  email and the email's body is blanked once it is sent).

  `consume/2` is the only way in, and it is one statement: it marks the token used **and** says
  which user it was for, if it is the right kind, not used and not expired. Two requests with
  the same link at once: one wins. A new link of a kind replaces the earlier ones.
  """
  import Ecto.Query

  alias App.Accounts.Models.UserToken
  alias App.Accounts.Settings
  alias Platform.Database.Repo

  @kinds ~w(reset confirm)
  @max_secret 200

  @spec issue(integer(), String.t()) :: String.t()
  def issue(user_id, kind) when kind in @kinds do
    secret = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    now = DateTime.utc_now()

    {:ok, _} =
      Repo.transact(fn ->
        from(t in UserToken,
          where: t.user_id == ^user_id and t.kind == ^kind and is_nil(t.used_at)
        )
        |> Repo.update_all(set: [used_at: now])

        {:ok,
         Repo.insert!(%UserToken{
           user_id: user_id,
           kind: kind,
           token_hash: hash(secret),
           expires_at: DateTime.add(now, ttl(kind), :second)
         })}
      end)

    secret
  end

  @doc "Uses the link up. `{:ok, user_id}`, or `{:error, :invalid}` for every way it can be wrong."
  @spec consume(term(), String.t()) :: {:ok, integer()} | {:error, :invalid}
  def consume(secret, kind)
      when is_binary(secret) and byte_size(secret) <= @max_secret and kind in @kinds do
    now = DateTime.utc_now()

    {_count, rows} =
      from(t in UserToken,
        where:
          t.token_hash == ^hash(secret) and t.kind == ^kind and is_nil(t.used_at) and
            t.expires_at > ^now,
        select: t.user_id
      )
      |> Repo.update_all(set: [used_at: now])

    case rows do
      [user_id] -> {:ok, user_id}
      [] -> {:error, :invalid}
    end
  end

  def consume(_secret, _kind), do: {:error, :invalid}

  @doc "Was a link of this kind made for the user in the last `seconds`?"
  @spec issued_within?(integer(), String.t(), non_neg_integer()) :: boolean()
  def issued_within?(user_id, kind, seconds) do
    since = DateTime.add(DateTime.utc_now(), -seconds, :second)

    Repo.exists?(
      from(t in UserToken,
        where: t.user_id == ^user_id and t.kind == ^kind and t.inserted_at > ^since
      )
    )
  end

  @doc "Removes links that ended (used or expired) more than a week ago. Returns how many."
  @spec prune() :: non_neg_integer()
  def prune do
    cutoff = DateTime.add(DateTime.utc_now(), -7 * 86_400, :second)

    {count, _} =
      from(t in UserToken,
        where: t.inserted_at < ^cutoff and (not is_nil(t.used_at) or t.expires_at < ^cutoff)
      )
      |> Repo.delete_all()

    count
  end

  defp hash(secret), do: :sha256 |> :crypto.hash(secret) |> Base.encode16(case: :lower)

  defp ttl("reset"), do: Settings.reset_ttl_seconds()
  defp ttl("confirm"), do: Settings.confirm_ttl_seconds()
end
