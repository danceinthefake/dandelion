defmodule Dandelion.Queue.OrderedTest do
  use Dandelion.DataCase, async: true

  alias Dandelion.Queue.Ordered

  defmodule Worker do
    use Oban.Worker, queue: :ordered
    def perform(_job), do: :ok
  end

  defp insert(key, n) do
    {:ok, job} = %{"n" => n} |> Worker.new() |> Ordered.insert(key)
    job
  end

  defp set_state(job, state),
    do: TestRepo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: state])

  test "a job waits for the earlier jobs of its key" do
    {first, second} = {insert("k:1", 1), insert("k:1", 2)}

    assert Ordered.turn(first) == :ok
    assert Ordered.turn(second) == {:snooze, 1}

    set_state(first, "completed")
    assert Ordered.turn(second) == :ok
  end

  test "another key doesn't wait" do
    _blocker = insert("k:2", 1)
    assert Ordered.turn(insert("k:3", 1)) == :ok
  end

  test "a discarded job stops blocking its key" do
    first = insert("k:4", 1)
    second = insert("k:4", 2)
    set_state(first, "discarded")
    assert Ordered.turn(second) == :ok
  end

  test "a running (executing) or retrying job still blocks" do
    for state <- ["executing", "retryable", "scheduled"] do
      first = insert("k:5:#{state}", 1)
      second = insert("k:5:#{state}", 2)
      set_state(first, state)
      assert Ordered.turn(second) == {:snooze, 1}, state
    end
  end

  test "insert keeps the key in the job's meta" do
    assert %{meta: %{"ordered_key" => "k:6"}} = insert("k:6", 1)
  end

  test "the index exists (Dandelion.Migration)" do
    assert %{rows: [[1]]} =
             TestRepo.query!(
               "SELECT 1 FROM pg_indexes WHERE indexname = 'oban_jobs_ordered_key_index'"
             )
  end
end
