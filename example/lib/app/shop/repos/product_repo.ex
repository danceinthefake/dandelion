defmodule Platform.Database.Repos.ProductRepo do
  @moduledoc "Product queries. ≈ `repo/products.go`."
  alias App.Shop.Models.Product
  alias Platform.Database.Repo

  @doc "A product, or nil."
  @spec get(String.t()) :: Product.t() | nil
  def get(sku), do: Repo.get(Product, sku)

  @doc "Saves a changeset (a new price)."
  def update(%Ecto.Changeset{} = changeset), do: Repo.update(changeset)
end
