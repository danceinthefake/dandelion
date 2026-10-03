defmodule Platform.Web.HealthHandler do
  @moduledoc """
  `GET /health` for load balancers and Kubernetes probes: 200 when the
  database answers, 503 when it doesn't — and within a few seconds either way
  (the query gives up after 2 s, and dropping the stuck connection takes a moment
  more): a database that hangs, with connections open and no answers, must not
  make the probe hang too. ≈ a Go `/healthz` handler with a `context.WithTimeout`.
  """
  use Platform.Web, :handler

  alias Platform.Database.Repo

  @timeout 2_000

  def show(conn, _params) do
    case Repo.query("SELECT 1", [], timeout: @timeout) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(:service_unavailable) |> json(%{status: "database down"})
    end
  end
end
