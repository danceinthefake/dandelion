defmodule Dandelion.Trace do
  @moduledoc false
  # Puts the current trace context into a job's `meta` (W3C `traceparent`), so
  # the job continues the trace of whatever queued it — on whichever node runs
  # it. `opentelemetry_oban` reads it back when the job starts.
  #
  # A no-op when OpenTelemetry isn't installed, or when no span is active.
  @compile {:no_warn_undefined, :otel_propagator_text_map}

  @spec propagate(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def propagate(changeset) do
    if Code.ensure_loaded?(:otel_propagator_text_map) do
      meta = Ecto.Changeset.get_field(changeset, :meta, %{})
      context = :otel_propagator_text_map.inject([]) |> Map.new()
      Ecto.Changeset.change(changeset, meta: Map.merge(meta, context))
    else
      changeset
    end
  end
end
