defmodule Platform.CacheTest do
  use ExUnit.Case, async: true

  alias Platform.Cache

  defp key, do: {:test, System.unique_integer()}

  test "fetch calls the function once, then serves the kept value" do
    key = key()
    {:ok, calls} = Agent.start_link(fn -> 0 end)
    load = fn -> Agent.update(calls, &(&1 + 1)) && :value end

    assert Cache.fetch(key, load) == :value
    assert Cache.fetch(key, load) == :value
    assert Agent.get(calls, & &1) == 1
  end

  test "nil is not kept" do
    key = key()
    assert Cache.fetch(key, fn -> nil end) == nil
    assert Cache.fetch(key, fn -> :now_there end) == :now_there
  end

  test "delete makes the next fetch load again" do
    key = key()
    assert Cache.fetch(key, fn -> 1 end) == 1
    Cache.delete(key)
    assert Cache.fetch(key, fn -> 2 end) == 2
  end

  test "a delete announced by another node clears the key here" do
    key = key()
    assert Cache.fetch(key, fn -> 1 end) == 1

    # what another node's Cache.delete/1 sends
    Phoenix.PubSub.broadcast(Platform.Broadcast, "cache", {:cache_delete, key})
    :sys.get_state(Platform.Cache.Listener)

    assert Cache.fetch(key, fn -> 2 end) == 2
  end

  test "a delete here is sent to other nodes, but not back to this process" do
    Phoenix.PubSub.subscribe(Platform.Broadcast, "cache")
    key = key()
    Cache.delete(key)
    refute_receive {:cache_delete, ^key}
  end
end
