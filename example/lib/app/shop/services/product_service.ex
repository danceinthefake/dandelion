defmodule App.Shop.Services.ProductService do
  @moduledoc """
  Products and their prices. ≈ `service/products.go`.

  Reads go through `Dandelion.Cache`; a price change is saved first, then the
  cached copy is removed on every node, so the next read on any node loads the
  new price.
  """
  alias App.Shop.Models.Product
  alias Dandelion.Cache
  alias Platform.Database.Repos.ProductRepo

  @doc "One product, from the cache when it's there."
  @spec get(String.t()) :: {:ok, Product.t()} | {:error, :not_found}
  def get(sku) do
    case Cache.fetch({:product, sku}, fn -> ProductRepo.get(sku) end) do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @doc "Sets a product's price (`%{\"price_cents\" => 1500}`)."
  @spec update_price(String.t(), map()) :: {:ok, Product.t()} | {:error, term()}
  def update_price(sku, params) do
    with %Product{} = product <- ProductRepo.get(sku) || {:error, :not_found},
         {:ok, product} <- product |> Product.price_changeset(params) |> ProductRepo.update() do
      # after the commit (a plain Repo.update is one), never before
      Cache.delete({:product, sku})
      {:ok, product}
    end
  end
end
