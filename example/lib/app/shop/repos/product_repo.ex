defmodule Platform.Database.Repos.ProductRepo do
  @moduledoc "Product queries. ≈ `repo/products.go`."
  alias App.Shop.Models.Product
  alias Platform.Database.Repo

  @doc "A product, or nil."
  @spec get(String.t()) :: Product.t() | nil
  def get(sku), do: Repo.get(Product, sku)

  @doc "Saves a changeset (a new price, a new name …)."
  def update(%Ecto.Changeset{} = changeset), do: Repo.update(changeset)

  def insert(%Ecto.Changeset{} = changeset), do: Repo.insert(changeset)

  def delete(%Product{} = product), do: Repo.delete(product)
end
