defmodule ShopWeb.Handlers.OrderJSON do
  @moduledoc """
  The JSON shape of orders. ≈ a Go response struct with `json:"…"` tags:
  what the API promises, independent of the database columns.
  """
  alias Shop.Models.{Order, OrderItem}

  def order(%Order{} = o) do
    %{
      id: o.id,
      customer_email: o.customer_email,
      status: o.status,
      total_cents: o.total_cents,
      items: Enum.map(o.items, &item/1),
      created_at: o.inserted_at,
      updated_at: o.updated_at
    }
  end

  def page(%{orders: orders, page: page, per_page: per_page}) do
    %{orders: Enum.map(orders, &order/1), page: page, per_page: per_page}
  end

  defp item(%OrderItem{} = i), do: %{sku: i.sku, quantity: i.quantity, price_cents: i.price_cents}
end
