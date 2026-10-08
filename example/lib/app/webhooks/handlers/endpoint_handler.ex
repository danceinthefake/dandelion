defmodule App.Webhooks.Handlers.EndpointHandler do
  @moduledoc """
  HTTP handlers for webhook endpoints. Admins only (the router's `:admin`
  pipeline). The secret is in the answer to creating one, and nowhere else.
  """
  use Platform.Web, :handler

  alias App.Webhooks.Handlers.EndpointJSON
  alias App.Webhooks.Services.EndpointService

  action_fallback Platform.Web.FallbackHandler

  # POST /api/webhooks   {"url": "https://example.com/hook", "events": ["order.created"]}
  def create(conn, params) do
    with {:ok, endpoint} <- EndpointService.create(params, conn.assigns.current_user) do
      conn |> put_status(:created) |> json(EndpointJSON.endpoint(endpoint, secret: true))
    end
  end

  # GET /api/webhooks
  def index(conn, _params),
    do: json(conn, %{endpoints: Enum.map(EndpointService.list(), &EndpointJSON.endpoint/1)})

  # DELETE /api/webhooks/:id
  def delete(conn, %{"id" => id}) do
    with {id, ""} <- Integer.parse(id),
         :ok <- EndpointService.delete(id, conn.assigns.current_user) do
      send_resp(conn, :no_content, "")
    else
      :error -> {:error, :not_found}
      {_, _rest} -> {:error, :not_found}
      other -> other
    end
  end
end
