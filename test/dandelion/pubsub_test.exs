defmodule Dandelion.PubSubTest do
  use Dandelion.DataCase, async: true

  alias Dandelion.PubSub

  defmodule A do
    use Oban.Worker
    def perform(_job), do: :ok
  end

  defmodule B do
    use Oban.Worker
    def perform(_job), do: :ok
  end

  @subs %{"thing.made" => [A, B], "thing.lonely" => []}

  test "one job per subscriber, each with the topic and payload" do
    assert [%Oban.Job{}, %Oban.Job{}] = PubSub.publish(@subs, "thing.made", %{"id" => 7})

    for worker <- [A, B],
        do: assert_enqueued(worker: worker, args: %{topic: "thing.made", payload: %{id: 7}})
  end

  test "a topic with no subscribers queues nothing" do
    assert PubSub.publish(@subs, "thing.lonely", %{}) == []
  end

  test "a topic that isn't listed is an error" do
    assert_raise ArgumentError, ~r/thing.typo/, fn -> PubSub.publish(@subs, "thing.typo", %{}) end
  end

  test "the events are saved with the caller's transaction, or not at all" do
    TestRepo.transaction(fn ->
      PubSub.publish(@subs, "thing.made", %{"id" => 8})
      TestRepo.rollback(:oops)
    end)

    refute_enqueued(worker: A, args: %{payload: %{id: 8}})
  end
end
