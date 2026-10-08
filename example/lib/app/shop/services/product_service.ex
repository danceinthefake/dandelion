defmodule App.Shop.Services.ProductService do
  @moduledoc """
  Products, their prices, and finding them. ≈ `service/products.go`.

  Reads go through `Dandelion.Cache`; a price change is saved first, then the
  cached copy is removed on every node, so the next read on any node loads the
  new price.
  """
  alias App.Audit.Services.AuditService
  alias App.Shop.Models.Product
  alias Dandelion.Cache
  alias Platform.Database.Repo
  alias Platform.Database.Repos.ProductRepo

  @search_limit 50

  @doc "One product, from the cache when it's there."
  @spec get(String.t()) :: {:ok, Product.t()} | {:error, :not_found}
  def get(sku) do
    case Cache.fetch({:product, sku}, fn -> ProductRepo.get(sku) end) do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @doc """
  Adds a product (an admin does). Searchable at once, on every node: the search column is
  kept by Postgres in the same transaction.
  """
  @spec create(map(), AuditService.viewer()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def create(params, viewer \\ nil) do
    Repo.transact(fn ->
      with {:ok, product} <- params |> Product.create_changeset() |> ProductRepo.insert() do
        AuditService.record(
          AuditService.actor(viewer),
          "product.created",
          "product:#{product.sku}",
          %{
            name: product.name,
            price_cents: product.price_cents
          }
        )

        {:ok, product}
      end
    end)
  end

  @doc "Changes a product's name and/or description."
  @spec update_details(String.t(), map(), AuditService.viewer()) ::
          {:ok, Product.t()} | {:error, term()}
  def update_details(sku, params, viewer \\ nil) do
    result =
      Repo.transact(fn ->
        with %Product{} = product <- ProductRepo.get(sku) || {:error, :not_found},
             {:ok, updated} <-
               product |> Product.details_changeset(params) |> ProductRepo.update() do
          AuditService.record(AuditService.actor(viewer), "product.updated", "product:#{sku}", %{
            fields:
              for(f <- [:name, :description], Map.get(product, f) != Map.get(updated, f), do: f)
          })

          {:ok, updated}
        end
      end)

    with {:ok, product} <- result do
      Cache.delete({:product, sku})
      {:ok, product}
    end
  end

  @doc "Removes a product (orders keep the lines they were made with)."
  @spec delete(String.t(), AuditService.viewer()) :: :ok | {:error, :not_found}
  def delete(sku, viewer \\ nil) do
    result =
      Repo.transact(fn ->
        with %Product{} = product <- ProductRepo.get(sku) || {:error, :not_found},
             {:ok, _} <- ProductRepo.delete(product) do
          AuditService.record(AuditService.actor(viewer), "product.deleted", "product:#{sku}", %{
            name: product.name
          })

          {:ok, product}
        end
      end)

    with {:ok, _} <- result do
      Cache.delete({:product, sku})
      :ok
    end
  end

  @doc """
  Finds products by words in their name or description (`Dandelion.Search`): every word is
  a prefix and all must match, accents don't matter, the name outranks the description, and
  a query that matches nothing falls back to similar names (`"match": "fuzzy"`).

  `params` (strings, from a query): `q`, `limit` (1..#{@search_limit}, default 10), `offset`
  (0..1000, default 0).
  """
  @spec search(map()) :: {:ok, map()} | {:error, {:invalid, String.t()}}
  def search(params) do
    with {:ok, q} <- query(params["q"]),
         {:ok, limit} <- number(params["limit"], 10, 1, @search_limit, "limit"),
         {:ok, offset} <- number(params["offset"], 0, 0, 1_000, "offset") do
      result =
        Dandelion.Search.search(Repo, "products", q,
          select: ["sku", "name", "price_cents"],
          snippet: "description",
          fuzzy: "name",
          order: "name",
          limit: limit,
          offset: offset
        )

      {:ok, Map.put(result, :query, q)}
    end
  end

  defp query(q) when is_binary(q) do
    if String.trim(q) == "",
      do: {:error, {:invalid, "q is required: the words to look for"}},
      else: {:ok, String.slice(q, 0, 200)}
  end

  defp query(_), do: {:error, {:invalid, "q is required: the words to look for"}}

  defp number(nil, default, _min, _max, _name), do: {:ok, default}

  defp number(value, _default, min, max, name) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n in min..max//1 -> {:ok, n}
      _ -> {:error, {:invalid, "#{name} must be a whole number from #{min} to #{max}"}}
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
