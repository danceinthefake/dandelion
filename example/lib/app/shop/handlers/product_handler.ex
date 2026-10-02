defmodule App.Shop.Handlers.ProductHandler do
  @moduledoc """
  HTTP handlers for products. ≈ `http/products.go`. Reading is public; changing
  a price needs an admin (the router's `:admin` pipeline).
  """
  use Platform.Web, :handler

  alias App.Shop.Services.ProductService

  action_fallback Platform.Web.FallbackHandler

  # GET /api/products/TEA-01
  def show(conn, %{"sku" => sku}) do
    with {:ok, product} <- ProductService.get(sku), do: json(conn, product_json(product))
  end

  # PUT /api/products/TEA-01   {"price_cents": 1600}
  def update(conn, %{"sku" => sku} = params) do
    with {:ok, product} <- ProductService.update_price(sku, params),
         do: json(conn, product_json(product))
  end

  defp product_json(p), do: %{sku: p.sku, name: p.name, price_cents: p.price_cents}
end
