defmodule Platform.Cache.Listener do
  @moduledoc """
  Keeps the node's cache in step with the others: removes keys that another
  node deleted (`Platform.Cache.delete/1`), and empties the cache when a node
  joins — the two sides may have missed each other's deletes while apart.
  """
  use GenServer

  @topic "cache"

  def topic, do: @topic

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Phoenix.PubSub.subscribe(Platform.Broadcast, @topic)
    :net_kernel.monitor_nodes(true)
    {:ok, nil}
  end

  @impl true
  def handle_info({:cache_delete, key}, state) do
    Cachex.del(Platform.Cache, key)
    {:noreply, state}
  end

  def handle_info({:nodeup, _node}, state) do
    Cachex.clear(Platform.Cache)
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}
end
