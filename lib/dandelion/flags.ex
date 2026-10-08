defmodule Dandelion.Flags do
  @moduledoc """
  Settings and feature flags that you change while the app runs, and every node
  sees. ≈ LaunchDarkly / Unleash / a Consul KV — kept in a table in Postgres, read
  through `Dandelion.Cache`.

  Start it after `Dandelion.Cache`, with your repo:

      {Dandelion.Flags, repo: MyApp.Repo}

  and add the table with a migration (after the Oban one):

      def up, do: Dandelion.Flags.Migration.up()
      def down, do: Dandelion.Flags.Migration.down()

  then:

      Flags.enabled?("checkout.new_flow")           # false until someone sets it
      Flags.get("search.page_size", 20)             # 20 until someone sets it
      Flags.put("checkout.new_flow", true)          # on, on every node
      Flags.delete("checkout.new_flow")             # back to the default

  A value is anything JSON can hold (a boolean, a number, a string, a map). A key is
  lowercase letters, digits and `. _ : -`, up to 100 characters.

  **Postgres decides; memory only makes it fast.** The value lives in the table. A
  read is served from the cache on the node, so it costs nothing and does not ask
  Postgres per request; `put/2` and `delete/1` save first, then clear the cached copy
  **on every node** (`Dandelion.Cache.delete/1`), so the next read anywhere loads the
  new value. A node that missed the message (a network split) serves the old value
  for at most the cache's TTL (a minute), then reads the table. A flag that is not
  set is cached too, so a read of a flag nobody has ever set doesn't go to Postgres
  each time either.

  **If Postgres can't be reached** and the value isn't cached, `get/2` returns the
  default you gave it (and logs), instead of failing the request: a flag that is a
  kill switch should default to the safe side, so choose the default for that.

  Call `put/2` and `delete/1` outside a transaction, or clear the cache yourself
  after yours commits: the cached copy must not be cleared before the change is
  visible, or another node loads the old value again.
  """
  require Logger

  alias Dandelion.Cache

  @key_format ~r/\A[a-z0-9_.:-]{1,100}\z/
  @max_value_bytes 10_000

  @doc false
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc false
  # Only remembers the repo; there is nothing to supervise.
  def start_link(opts) do
    :persistent_term.put({__MODULE__, :repo}, Keyword.fetch!(opts, :repo))
    :ignore
  end

  @doc "The flag's value, or `default` when it isn't set (or can't be read)."
  @spec get(String.t(), term()) :: term()
  def get(key, default \\ nil) when is_binary(key) do
    case Cache.fetch({:flag, key}, fn -> load(key) end) do
      {:set, value} -> value
      _ -> default
    end
  end

  @doc "True when the flag is set to `true`; `default` when it isn't set."
  @spec enabled?(String.t(), boolean()) :: boolean()
  def enabled?(key, default \\ false), do: get(key, default) == true

  @doc """
  Sets a flag, on every node. Returns the value.

  `in_transaction: fun` runs `fun` in the same transaction as the change, before it
  commits — the place for a `Dandelion.Audit.record/4`: the change and its record are
  saved together. If `fun` raises, the flag is not changed.
  """
  @spec put(String.t(), term(), keyword()) ::
          {:ok, term()} | {:error, :invalid_key | :invalid_value}
  def put(key, value, opts \\ []) do
    with :ok <- check_key(key), :ok <- check_value(value) do
      changed(opts, fn ->
        repo().query!(
          """
          INSERT INTO dandelion_flags (key, value, updated_at) VALUES ($1, $2, now())
          ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()
          """,
          [key, value]
        )
      end)

      Cache.delete({:flag, key})
      {:ok, value}
    end
  end

  @doc "Unsets a flag, on every node. Takes `in_transaction:` like `put/3`."
  @spec delete(String.t(), keyword()) :: :ok | {:error, :invalid_key}
  def delete(key, opts \\ []) do
    with :ok <- check_key(key) do
      changed(opts, fn -> repo().query!("DELETE FROM dandelion_flags WHERE key = $1", [key]) end)
      Cache.delete({:flag, key})
      :ok
    end
  end

  @doc "Every flag that is set, by key: `[%{key: …, value: …, updated_at: …}]`."
  @spec all() :: [%{key: String.t(), value: term(), updated_at: DateTime.t()}]
  def all do
    %{rows: rows} =
      repo().query!("SELECT key, value, updated_at FROM dandelion_flags ORDER BY key")

    for [key, value, updated_at] <- rows,
        do: %{key: key, value: value, updated_at: DateTime.from_naive!(updated_at, "Etc/UTC")}
  end

  @doc "Whether `key` is a valid flag key."
  def valid_key?(key), do: is_binary(key) and key =~ @key_format

  # -- inside ----------------------------------------------------------------------

  # The cache doesn't keep nil, so "not set" is a value of its own; and a read that
  # failed is nil, which is not kept either: it is asked again at the next read.
  defp load(key) do
    case repo().query("SELECT value FROM dandelion_flags WHERE key = $1", [key]) do
      {:ok, %{rows: [[value]]}} ->
        {:set, value}

      {:ok, %{rows: []}} ->
        :unset

      {:error, error} ->
        Logger.warning("Dandelion.Flags: can't read #{key}: #{Exception.message(error)}")
        nil
    end
  end

  # the change, and what the caller wants saved with it, in one transaction
  defp changed(opts, change) do
    {:ok, _} =
      repo().transaction(fn ->
        change.()
        if fun = opts[:in_transaction], do: fun.()
      end)

    :ok
  end

  defp check_key(key), do: if(valid_key?(key), do: :ok, else: {:error, :invalid_key})

  defp check_value(value) do
    case Jason.encode(value) do
      {:ok, json} when byte_size(json) <= @max_value_bytes -> :ok
      _ -> {:error, :invalid_value}
    end
  end

  defp repo, do: :persistent_term.get({__MODULE__, :repo})
end
