defmodule Dandelion.ResilienceTest do
  use ExUnit.Case, async: false

  alias Dandelion.Resilience

  setup do
    start_supervised!(Resilience)
    :ok
  end

  defp counter, do: :counters.new(1, [])

  defp bump(c) do
    :counters.add(c, 1, 1)
    :counters.get(c, 1)
  end

  defp count(c), do: :counters.get(c, 1)

  test "a call that works returns its value" do
    assert {:ok, 1} = Resilience.call(:a, fn -> {:ok, 1} end)
    assert Resilience.state(:a) == :closed
  end

  test "an error, a raise, an exit and a stray value are all {:error, _}" do
    assert {:error, :nope} = Resilience.call(:a, fn -> {:error, :nope} end)
    assert {:error, {:raised, %RuntimeError{}}} = Resilience.call(:a, fn -> raise "boom" end)
    assert {:error, {:exit, _}} = Resilience.call(:a, fn -> exit(:bad) end)
    assert {:error, {:unexpected, :oops}} = Resilience.call(:a, fn -> :oops end)
  end

  test "a call that takes too long is killed" do
    parent = self()

    assert {:error, :timeout} =
             Resilience.call(
               :slow,
               fn ->
                 send(parent, {:pid, self()})
                 Process.sleep(5_000)
               end,
               timeout: 50
             )

    assert_receive {:pid, pid}
    refute Process.alive?(pid)
  end

  test "retries a failure, with a growing wait, and stops at the limit" do
    c = counter()
    started = System.monotonic_time(:millisecond)

    assert {:error, :down} =
             Resilience.call(
               :r,
               fn ->
                 bump(c)
                 {:error, :down}
               end, retries: 2, backoff: 20)

    assert count(c) == 3
    # 20 + 40 ms, less jitter
    assert System.monotonic_time(:millisecond) - started >= 40
  end

  test "stops retrying once a call works" do
    c = counter()

    assert {:ok, :up} =
             Resilience.call(
               :r,
               fn -> if bump(c) < 3, do: {:error, :down}, else: {:ok, :up} end,
               retries: 5,
               backoff: 1
             )

    assert count(c) == 3
  end

  test "retry? says which errors are worth another try" do
    c = counter()

    assert {:error, :bad_request} =
             Resilience.call(
               :r,
               fn ->
                 bump(c)
                 {:error, :bad_request}
               end,
               retries: 3,
               backoff: 1,
               retry?: &(&1 != :bad_request)
             )

    assert count(c) == 1
  end

  describe "the circuit" do
    defp fail_n(name, n, opts) do
      for _ <- 1..n, do: Resilience.call(name, fn -> {:error, :down} end, opts)
    end

    test "opens after the threshold, and then does not call at all" do
      c = counter()
      fail_n(:c, 3, failure_threshold: 3)
      assert Resilience.state(:c) == :open

      assert {:error, :circuit_open} =
               Resilience.call(:c, fn ->
                 bump(c)
                 {:ok, 1}
               end)

      assert count(c) == 0
    end

    test "failures must be in a row: a success starts the count again" do
      fail_n(:c, 2, failure_threshold: 3)
      assert {:ok, _} = Resilience.call(:c, fn -> {:ok, 1} end)
      fail_n(:c, 2, failure_threshold: 3)
      assert Resilience.state(:c) == :closed
    end

    test "a circuit is per name" do
      fail_n(:one, 2, failure_threshold: 2)
      assert Resilience.state(:one) == :open
      assert {:ok, 1} = Resilience.call(:two, fn -> {:ok, 1} end)
    end

    test "after reset_after one call is let through; success closes it" do
      fail_n(:c, 2, failure_threshold: 2, reset_after: 30)
      Process.sleep(40)
      assert {:ok, :back} = Resilience.call(:c, fn -> {:ok, :back} end, reset_after: 30)
      assert Resilience.state(:c) == :closed
    end

    test "a failed probe opens it again" do
      fail_n(:c, 2, failure_threshold: 2, reset_after: 30)
      Process.sleep(40)
      assert {:error, :down} = Resilience.call(:c, fn -> {:error, :down} end, reset_after: 30)
      assert Resilience.state(:c) == :open
      assert {:error, :circuit_open} = Resilience.call(:c, fn -> {:ok, 1} end, reset_after: 30)
    end

    test "only one caller probes at a time" do
      fail_n(:c, 2, failure_threshold: 2, reset_after: 30)
      Process.sleep(40)
      c = counter()
      parent = self()

      slow = fn ->
        send(parent, :probing)
        Process.sleep(150)
        bump(c)
        {:ok, 1}
      end

      task = Task.async(fn -> Resilience.call(:c, slow, reset_after: 30) end)
      assert_receive :probing

      assert {:error, :circuit_open} = Resilience.call(:c, fn -> {:ok, 2} end, reset_after: 30)
      assert {:ok, 1} = Task.await(task)
      assert count(c) == 1
    end

    test "retries count as one failure toward the threshold" do
      Resilience.call(:c, fn -> {:error, :down} end, failure_threshold: 2, retries: 3, backoff: 1)
      assert Resilience.state(:c) == :closed
      Resilience.call(:c, fn -> {:error, :down} end, failure_threshold: 2, retries: 3, backoff: 1)
      assert Resilience.state(:c) == :open
    end
  end

  test "emits telemetry for calls and circuit changes" do
    ref = make_ref()
    me = self()

    :telemetry.attach_many(
      "resilience-test-#{inspect(ref)}",
      [[:dandelion, :resilience, :call], [:dandelion, :resilience, :circuit]],
      fn event, m, meta, _ -> send(me, {ref, event, m, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach("resilience-test-#{inspect(ref)}") end)

    Resilience.call(:t, fn -> {:error, :x} end, failure_threshold: 1)

    assert_receive {^ref, [:dandelion, :resilience, :call], %{duration: _},
                    %{name: :t, result: :error}}

    assert_receive {^ref, [:dandelion, :resilience, :circuit], _, %{name: :t, state: :open}}
  end
end
