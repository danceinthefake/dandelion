defmodule App.Settings.Handlers.FlagHandler do
  @moduledoc "HTTP handlers for flags. Admins only (the router's `:admin` pipeline)."
  use Platform.Web, :handler

  alias App.Settings.Services.FlagService

  action_fallback Platform.Web.FallbackHandler

  # GET /api/flags
  def index(conn, _params) do
    json(conn, %{
      flags:
        for(f <- FlagService.list(), do: %{key: f.key, value: f.value, updated_at: f.updated_at})
    })
  end

  # PUT /api/flags/orders.enabled   {"value": false}
  def update(conn, %{"key" => key, "value" => value}) do
    with {:ok, flag} <- FlagService.put(key, value), do: json(conn, flag)
  end

  def update(_conn, _params), do: {:error, {:invalid, "send {\"value\": …}"}}

  # DELETE /api/flags/orders.enabled
  def delete(conn, %{"key" => key}) do
    with :ok <- FlagService.delete(key), do: send_resp(conn, :no_content, "")
  end
end
