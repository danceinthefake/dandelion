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

  # POST /api/products   {"sku": "TEA-03", "name": "Oolong", "description": "…", "price_cents": 1800}
  def create(conn, params) do
    with {:ok, product} <- ProductService.create(params, conn.assigns.current_user) do
      conn |> put_status(:created) |> json(product_json(product))
    end
  end

  # PUT /api/products/TEA-01/details   {"name": "…", "description": "…"}
  def update_details(conn, %{"sku" => sku} = params) do
    with {:ok, product} <- ProductService.update_details(sku, params, conn.assigns.current_user),
         do: json(conn, product_json(product))
  end

  # DELETE /api/products/TEA-01
  def delete(conn, %{"sku" => sku}) do
    with :ok <- ProductService.delete(sku, conn.assigns.current_user),
         do: send_resp(conn, :no_content, "")
  end

  # PUT /api/products/TEA-01   {"price_cents": 1600}
  def update(conn, %{"sku" => sku} = params) do
    with {:ok, product} <- ProductService.update_price(sku, params, conn.assigns.current_user),
         do: json(conn, product_json(product))
  end

  defp product_json(p) do
    base = %{sku: p.sku, name: p.name, price_cents: p.price_cents}
    if p.description, do: Map.put(base, :description, p.description), else: base
  end
end
