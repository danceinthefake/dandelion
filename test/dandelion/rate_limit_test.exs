defmodule Dandelion.RateLimitTest do
  use ExUnit.Case, async: false

  alias Dandelion.RateLimit

  setup do
    start_supervised!(RateLimit)
    :ok
  end

  test "allows up to the limit, then denies with a wait" do
    assert {:allow, 1} = RateLimit.hit(:a, 2, 60_000)
    assert {:allow, 2} = RateLimit.hit(:a, 2, 60_000)
    assert {:deny, wait} = RateLimit.hit(:a, 2, 60_000)
    assert wait in 1..60_000
  end

  test "keys are counted apart" do
    assert {:allow, 1} = RateLimit.hit(:a, 1, 60_000)
    assert {:deny, _} = RateLimit.hit(:a, 1, 60_000)
    assert {:allow, 1} = RateLimit.hit(:b, 1, 60_000)
  end

  test "a new window starts from zero" do
    assert {:allow, 1} = RateLimit.hit(:a, 1, 50)
    assert {:deny, wait} = RateLimit.hit(:a, 1, 50)
    Process.sleep(wait + 5)
    assert {:allow, 1} = RateLimit.hit(:a, 1, 50)
  end

  test "reset forgets the counts" do
    RateLimit.hit(:a, 1, 60_000)
    RateLimit.reset()
    assert {:allow, 1} = RateLimit.hit(:a, 1, 60_000)
  end

  test "the sweep removes windows that ended" do
    RateLimit.hit(:a, 1, 10)
    Process.sleep(30)
    send(RateLimit, :sweep)
    :sys.get_state(RateLimit)
    assert :ets.info(RateLimit, :size) == 0
  end
end
