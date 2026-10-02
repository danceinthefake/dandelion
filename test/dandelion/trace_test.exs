defmodule Dandelion.TraceTest do
  use Dandelion.DataCase, async: true

  require OpenTelemetry.Tracer, as: Tracer

  alias Dandelion.{PubSub, Trace}
  alias Dandelion.Queue.Ordered

  defmodule Worker do
    use Oban.Worker
    def perform(_job), do: :ok
  end

  defp traceparent(%{meta: meta}), do: meta["traceparent"]

  test "the job's meta gets the trace context of the active span" do
    Tracer.with_span "request" do
      ctx = Tracer.current_span_ctx()

      trace_id =
        ctx |> OpenTelemetry.Span.trace_id() |> Integer.to_string(16) |> String.downcase()

      changeset = %{} |> Worker.new() |> Trace.propagate()
      assert "00-" <> _ = traceparent(changeset.changes)
      assert traceparent(changeset.changes) =~ String.pad_leading(trace_id, 32, "0")
    end
  end

  test "no active span: nothing is added" do
    changeset = %{} |> Worker.new(meta: %{"a" => 1}) |> Trace.propagate()
    assert changeset.changes.meta == %{"a" => 1}
  end

  test "existing meta is kept" do
    Tracer.with_span "request" do
      changeset = %{} |> Worker.new(meta: %{"keep" => "me"}) |> Trace.propagate()
      assert %{"keep" => "me", "traceparent" => _} = changeset.changes.meta
    end
  end

  test "published events carry the trace context to every subscriber" do
    Tracer.with_span "request" do
      jobs = PubSub.publish(%{"t" => [Worker, Worker]}, "t", %{})
      assert length(jobs) == 2
      assert Enum.all?(jobs, &(traceparent(&1) =~ ~r/^00-[0-9a-f]{32}-[0-9a-f]{16}-0[01]$/))
    end
  end

  test "ordered jobs carry it too, next to their key" do
    Tracer.with_span "request" do
      {:ok, job} = %{} |> Worker.new() |> Ordered.insert("order:1")
      assert %{"ordered_key" => "order:1", "traceparent" => _} = job.meta
    end
  end

  test "outside a span, published events work as before" do
    assert [job] = PubSub.publish(%{"t" => [Worker]}, "t", %{})
    refute Map.has_key?(job.meta, "traceparent")
  end
end
