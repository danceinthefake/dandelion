defmodule Platform.Web.HealthHandler do
  @moduledoc """
  `GET /health` for load balancers and Kubernetes probes: 200 when the
  database answers, 503 when it doesn't. ≈ a Go `/healthz` handler.
  """
  use Platform.Web, :handler

  alias Platform.Database.Repo

  def show(conn, _params) do
    case Repo.query("SELECT 1") do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(:service_unavailable) |> json(%{status: "database down"})
    end
  end
end
