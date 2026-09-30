defmodule Dandelion.Cache do
  @moduledoc """
  A cache in memory, on each node. ≈ Redis / Memcached used as a cache —
  but it lives inside the app ([Cachex](https://hexdocs.pm/cachex)), so a
  read costs no network trip.

  Start it in your supervision tree, after your `Phoenix.PubSub`:

      {Dandelion.Cache, pubsub: MyApp.Broadcast}

  then:

      Cache.fetch({:product, sku}, fn -> Repo.get(Product, sku) end)
      Cache.delete({:product, sku})

    * `fetch/2` returns the cached value, or calls the function, keeps what
      it returns (`nil` is not kept) and returns that. Concurrent misses for
      one key call the function once.
    * `delete/1` clears the key **on every node** (over the PubSub). Call it
      **after** the database change is committed: earlier, another node could
      read the old row and cache it again.
    * Entries expire after `:ttl` (default one minute), so a missed message
      (a network split) fixes itself quickly. A node that joins or rejoins
      the cluster clears its whole cache (`Dandelion.Cache.Listener`).

  Options: `:pubsub` (required, the name of your `Phoenix.PubSub`) and `:ttl`
  in milliseconds.

  It is a cache: a node that restarts starts empty. Anything that must
  survive goes in Postgres.

  One cache per app: the name is `Dandelion.Cache`.
  """
  import Cachex.Spec

  alias Dandelion.Cache.Listener

  @ttl :timer.minutes(1)

  @doc false
  def child_spec(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)
    ttl = Keyword.get(opts, :ttl, @ttl)

    %{
      id: __MODULE__,
      type: :supervisor,
      start:
        {Supervisor, :start_link,
         [
           [
             {Cachex, name: __MODULE__, expiration: expiration(default: ttl)},
             {Listener, pubsub: pubsub}
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
    pubsub = Listener.pubsub()
    Phoenix.PubSub.broadcast_from(pubsub, self(), Listener.topic(), {:cache_delete, key})
  end
end
