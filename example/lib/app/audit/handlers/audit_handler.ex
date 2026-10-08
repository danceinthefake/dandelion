defmodule App.Audit.Handlers.AuditHandler do
  @moduledoc "Reading the audit log. Admins only (the router's `:admin` pipeline)."
  use Platform.Web, :handler

  alias App.Audit.Services.AuditService

  action_fallback Platform.Web.FallbackHandler

  # GET /api/audit?actor=user:5&action=order.&subject=order:42&before=1000&limit=50
  def index(conn, params) do
    with {:ok, entries} <- AuditService.list(params) do
      json(conn, %{
        entries: Enum.map(entries, &entry/1),
        next_before: next_before(entries, params)
      })
    end
  end

  defp entry(e), do: Map.take(e, [:id, :at, :actor, :action, :subject, :details, :request_id])

  # pass this as `before` to get the next page; nil when this page is the last
  defp next_before(entries, params) do
    limit =
      params
      |> Map.get("limit", "50")
      |> to_string()
      |> Integer.parse()
      |> then(fn
        {n, _} -> n
        _ -> 50
      end)

    if length(entries) >= min(limit, 200), do: List.last(entries).id
  end
end
