defmodule Platform.Cache do
  @moduledoc """
  A cache in memory, on each node. ≈ Redis / Memcached used as a cache —
  but it lives inside the app ([Cachex](https://hexdocs.pm/cachex)), so a
  read costs no network trip.

      Cache.fetch({:product, sku}, fn -> Repo.get(Product, sku) end)
      Cache.delete({:product, sku})

    * `fetch/2` returns the cached value, or calls the function, keeps what
      it returns (`nil` is not kept) and returns that. Concurrent misses for
      one key call the function once.
    * `delete/1` clears the key **on every node** (`Platform.Broadcast`). Call
      it **after** the database change is committed: earlier, another node
      could read the old row and cache it again.
    * Entries expire after #{div(:timer.minutes(1), 1000)} s, so a missed
      message (a network split) fixes itself quickly. A node that joins or
      rejoins the cluster clears its whole cache (`Platform.Cache.Listener`).

  It is a cache: a node that restarts starts empty. Anything that must
  survive goes in Postgres (DESIGN §10.3, rule 1).
  """
  import Cachex.Spec

  alias Platform.Cache.Listener

  @ttl :timer.minutes(1)

  @doc false
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      type: :supervisor,
      start:
        {Supervisor, :start_link,
         [
           [
             {Cachex, name: __MODULE__, expiration: expiration(default: @ttl)},
             Listener
           ],
           [strategy: :one_for_one]
         ]}
    }
  end

  @doc "The value for `key`, from the cache or from `fun` (not kept if `nil`)."
  @spec fetch(term(), (-> term())) :: term()
  def fetch(key, fun) do
    {_status, value} =
      Cachex.fetch(__MODULE__, key, fn _key ->
        case fun.() do
          nil -> {:ignore, nil}
          value -> {:commit, value}
        end
      end)

    value
  end

  @doc "Removes `key` on this node and on every other node."
  @spec delete(term()) :: :ok
  def delete(key) do
    Cachex.del(__MODULE__, key)

    Phoenix.PubSub.broadcast_from(
      Platform.Broadcast,
      self(),
      Listener.topic(),
      {:cache_delete, key}
    )
  end
end
