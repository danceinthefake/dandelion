defmodule Dandelion.Cache.Listener do
  @moduledoc """
  Keeps the node's cache in step with the others: removes keys that another
  node deleted (`Dandelion.Cache.delete/1`), and empties the cache when a node
  joins — the two sides may have missed each other's deletes while apart.
  """
  use GenServer

  @topic "dandelion:cache"

  def topic, do: @topic

  @doc "The PubSub this node's cache announces deletes on."
  def pubsub, do: :persistent_term.get({__MODULE__, :pubsub})

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)
    :persistent_term.put({__MODULE__, :pubsub}, pubsub)
    Phoenix.PubSub.subscribe(pubsub, @topic)
    :net_kernel.monitor_nodes(true)
    {:ok, nil}
  end

  @impl true
  def handle_info({:cache_delete, key}, state) do
    Cachex.del(Dandelion.Cache, key)
    {:noreply, state}
  end

  def handle_info({:nodeup, _node}, state) do
    Cachex.clear(Dandelion.Cache)
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}
end
