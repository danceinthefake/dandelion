defmodule App.Shop.Services.ProductService do
  @moduledoc """
  Products and their prices. ≈ `service/products.go`.

  Reads go through `Dandelion.Cache`; a price change is saved first, then the
  cached copy is removed on every node, so the next read on any node loads the
  new price.
  """
  alias App.Audit.Services.AuditService
  alias App.Shop.Models.Product
  alias Dandelion.Cache
  alias Platform.Database.Repo
  alias Platform.Database.Repos.ProductRepo

  @doc "One product, from the cache when it's there."
  @spec get(String.t()) :: {:ok, Product.t()} | {:error, :not_found}
  def get(sku) do
    case Cache.fetch({:product, sku}, fn -> ProductRepo.get(sku) end) do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @doc "Sets a product's price (`%{\"price_cents\" => 1500}`), and records who changed it, from and to."
  @spec update_price(String.t(), map(), AuditService.viewer()) ::
          {:ok, Product.t()} | {:error, term()}
  def update_price(sku, params, viewer \\ nil) do
    result =
      Repo.transact(fn ->
        with %Product{} = product <- ProductRepo.get(sku) || {:error, :not_found},
             {:ok, updated} <- product |> Product.price_changeset(params) |> ProductRepo.update() do
          AuditService.record(
            AuditService.actor(viewer),
            "product.price_changed",
            "product:#{sku}",
            %{
              from: product.price_cents,
              to: updated.price_cents
            }
          )

          {:ok, updated}
        end
      end)

    # after the commit, never before
    with {:ok, product} <- result do
      Cache.delete({:product, sku})
      {:ok, product}
    end
  end
end
