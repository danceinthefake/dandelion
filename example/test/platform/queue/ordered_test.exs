defmodule Platform.Queue.OrderedTest do
  use Platform.DataCase, async: true
  use Oban.Testing, repo: Platform.Database.Repo

  alias App.Shop.Workers.ProcessPaymentEvent
  alias Platform.Database.Repo
  alias Platform.Queue.Ordered

  defp insert(key, n) do
    {:ok, job} =
      %{"event_id" => "#{key}-#{n}", "type" => "payment.succeeded", "order_id" => 1}
      |> ProcessPaymentEvent.new()
      |> Ordered.insert(key)

    job
  end

  defp finish(job),
    do: Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: "completed"])

  test "a job waits for the earlier jobs of its key" do
    {first, second} = {insert("k:1", 1), insert("k:1", 2)}

    assert Ordered.turn(first) == :ok
    assert Ordered.turn(second) == {:snooze, 1}

    finish(first)
    assert Ordered.turn(second) == :ok
  end

  test "another key doesn't wait" do
    _blocker = insert("k:2", 1)
    assert Ordered.turn(insert("k:3", 1)) == :ok
  end

  test "a discarded job stops blocking its key" do
    first = insert("k:4", 1)
    second = insert("k:4", 2)
    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.id), set: [state: "discarded"])
    assert Ordered.turn(second) == :ok
  end
end
