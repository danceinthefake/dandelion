defmodule Platform.Web.MetricsHandler do
  @moduledoc """
  `GET /metrics` for Prometheus. ≈ the `promhttp` handler in a Go service.

  It exposes how the service is doing inside, so keep it off the public
  internet: scrape the nodes from your private network. Setting `METRICS_TOKEN`
  also requires `Authorization: Bearer <token>` (Prometheus can send one:
  `authorization: { credentials: … }` in the scrape config).
  """
  use Platform.Web, :handler

  alias Platform.Web.Telemetry

  def show(conn, _params) do
    if allowed?(conn) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, Telemetry.scrape())
    else
      conn |> put_status(:unauthorized) |> json(%{error: "bad token"})
    end
  end

  defp allowed?(conn) do
    case Application.get_env(:acme, :metrics_token) do
      nil ->
        true

      token ->
        given = conn |> get_req_header("authorization") |> List.first("")
        Plug.Crypto.secure_compare(given, "Bearer " <> token)
    end
  end
end
