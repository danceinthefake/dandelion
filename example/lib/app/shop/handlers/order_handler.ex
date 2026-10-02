defmodule App.Shop.Handlers.OrderHandler do
  @moduledoc """
  HTTP handlers for orders. Every route needs a login (see the router); a
  customer sees only their own orders. ≈ `http/orders.go`: read the request, call the
  service, write JSON. Errors go to `Platform.Web.FallbackHandler`
  (`action_fallback`), so each action only handles the happy path.
  """
  use Platform.Web, :handler

  alias App.Shop.Handlers.OrderJSON
  alias App.Shop.Services.OrderService

  action_fallback Platform.Web.FallbackHandler

  # POST /api/orders
  # {"customer_email": "sari@example.com", "items": [{"sku": "TEA-01", "quantity": 2}]}
  # (prices come from the products table; see OrderService.create/1)
  def create(conn, params) do
    with {:ok, order} <- OrderService.create(params, viewer(conn)) do
      conn |> put_status(:created) |> json(OrderJSON.order(order))
    end
  end

  # GET /api/orders/:id
  def show(conn, %{"id" => id}) do
    with {:ok, id} <- id(id),
         {:ok, order} <- OrderService.get(id, viewer(conn)) do
      json(conn, OrderJSON.order(order))
    end
  end

  # GET /api/orders?status=pending&page=1&per_page=20
  def index(conn, params) do
    with {:ok, page} <- OrderService.list(params, viewer(conn)) do
      json(conn, OrderJSON.page(page))
    end
  end

  # POST /api/orders/:id/cancel
  def cancel(conn, %{"id" => id}) do
    with {:ok, id} <- id(id),
         {:ok, order} <- OrderService.cancel(id, viewer(conn)) do
      json(conn, OrderJSON.order(order))
    end
  end

  # The logged-in user (App.Accounts.Handlers.Auth put them there): the service
  # decides what they may see.
  defp viewer(conn), do: conn.assigns.current_user

  # Path ids are strings; anything that isn't a positive bigint is 404.
  defp id(value) do
    case Integer.parse(value) do
      {id, ""} when id in 1..9_223_372_036_854_775_807//1 -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
