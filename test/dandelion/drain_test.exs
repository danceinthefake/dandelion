defmodule Dandelion.DrainTest do
  use ExUnit.Case, async: false

  alias Dandelion.Drain

  setup do
    Drain.reset()
    on_exit(&Drain.reset/0)
  end

  test "a node is not draining until told, then stays so" do
    refute Drain.draining?()
    assert :ok = Drain.start(0)
    assert Drain.draining?()
  end

  test "start waits for the delay, so a load balancer can notice" do
    {us, _} = :timer.tc(fn -> Drain.start(60) end)
    assert us >= 55_000
  end
end
