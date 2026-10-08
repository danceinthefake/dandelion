defmodule Dandelion.FlagsTest do
  use Dandelion.DataCase, async: false

  alias Dandelion.{Cache, Flags}

  defmodule DownRepo do
    def query(_sql, _params), do: {:error, %RuntimeError{message: "database is down"}}
  end

  setup do
    start_supervised!({Phoenix.PubSub, name: Dandelion.TestPubSub})
    start_supervised!({Cache, pubsub: Dandelion.TestPubSub})
    Flags.start_link(repo: Dandelion.TestRepo)
    :ok
  end

  defp key, do: "test.flag-#{System.unique_integer([:positive])}"

  test "a flag nobody set is the default" do
    k = key()
    assert Flags.get(k) == nil
    assert Flags.get(k, 20) == 20
    refute Flags.enabled?(k)
    assert Flags.enabled?(k, true)
  end

  test "put, get, enabled?, and delete" do
    k = key()
    assert {:ok, true} = Flags.put(k, true)
    assert Flags.enabled?(k)
    assert {:ok, 50} = Flags.put(k, 50)
    assert Flags.get(k, 1) == 50
    refute Flags.enabled?(k)
    assert {:ok, %{"mode" => "b"}} = Flags.put(k, %{"mode" => "b"})
    assert Flags.get(k) == %{"mode" => "b"}
    assert :ok = Flags.delete(k)
    assert Flags.get(k, :default) == :default
  end

  test "false and zero are values, not 'unset'" do
    k = key()
    Flags.put(k, false)
    assert Flags.get(k, true) == false
    Flags.put(k, 0)
    assert Flags.get(k, 5) == 0
  end

  test "all lists what is set" do
    a = key()
    b = key()
    Flags.put(a, 1)
    Flags.put(b, "x")
    keys = Enum.map(Flags.all(), & &1.key)
    assert a in keys and b in keys
    assert %{value: "x", updated_at: %DateTime{}} = Enum.find(Flags.all(), &(&1.key == b))
  end

  test "bad keys and values are refused" do
    for bad <- ["", "Upper", "has space", "x/y", String.duplicate("a", 101), nil, 5] do
      assert {:error, :invalid_key} = Flags.put(bad, true), inspect(bad)
    end

    assert {:error, :invalid_value} = Flags.put(key(), self())
    assert {:error, :invalid_value} = Flags.put(key(), String.duplicate("x", 10_001))
  end

  test "a read is served from memory: Postgres is asked once" do
    k = key()
    Flags.put(k, "one")
    assert Flags.get(k) == "one"

    # changed behind the cache's back: the cached copy is still served …
    Dandelion.TestRepo.query!("UPDATE dandelion_flags SET value = '\"two\"' WHERE key = $1", [k])
    assert Flags.get(k) == "one"

    # … until it is cleared (what put/2 does, on every node)
    Cache.delete({:flag, k})
    assert Flags.get(k) == "two"
  end

  test "put clears the cached copy, so the next read sees the new value" do
    k = key()
    Flags.put(k, "one")
    assert Flags.get(k) == "one"
    Flags.put(k, "two")
    assert Flags.get(k) == "two"
  end

  test "a flag that is not set is remembered too: not looked up again" do
    k = key()
    assert Flags.get(k) == nil
    Dandelion.TestRepo.query!("INSERT INTO dandelion_flags VALUES ($1, 'true', now())", [k])
    assert Flags.get(k) == nil
    Cache.delete({:flag, k})
    assert Flags.get(k) == true
  end

  test "when Postgres can't be read, the default is returned and nothing is remembered" do
    k = key()
    Flags.put(k, "real")
    Cache.delete({:flag, k})

    :persistent_term.put({Flags, :repo}, DownRepo)
    on_exit(fn -> :persistent_term.put({Flags, :repo}, Dandelion.TestRepo) end)

    assert Flags.get(k, :safe) == :safe
    :persistent_term.put({Flags, :repo}, Dandelion.TestRepo)
    assert Flags.get(k, :safe) == "real"
  end

  test "in_transaction runs with the change, and a failure there undoes it" do
    k = key()
    me = self()

    assert {:ok, 1} = Flags.put(k, 1, in_transaction: fn -> send(me, :in_the_transaction) end)
    assert_received :in_the_transaction

    assert_raise RuntimeError, "audit failed", fn ->
      Flags.put(k, 2, in_transaction: fn -> raise "audit failed" end)
    end

    Cache.delete({:flag, k})
    assert Flags.get(k) == 1

    assert_raise RuntimeError, fn -> Flags.delete(k, in_transaction: fn -> raise "no" end) end
    assert Flags.get(k) == 1
    assert :ok = Flags.delete(k, in_transaction: fn -> :ok end)
    assert Flags.get(k) == nil
  end
end
