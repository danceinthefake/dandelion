defmodule App.Shop.Handlers.ProductSearchHandler do
  @moduledoc """
  `GET /api/search/products?q=gre+tea&limit=10&offset=0` — finding products. Public, like
  the catalogue. The snippet marks matching words with `[[` and `]]` and is **plain text**:
  the description is whatever an admin typed, so a client must escape it before it turns
  `[[…]]` into bold.
  """
  use Platform.Web, :handler

  alias App.Shop.Services.ProductService

  action_fallback Platform.Web.FallbackHandler

  def index(conn, params) do
    with {:ok, result} <- ProductService.search(params) do
      json(conn, %{
        query: result.query,
        match: result.match,
        total: result.total,
        results: Enum.map(result.rows, &row/1)
      })
    end
  end

  defp row(r) do
    %{
      sku: r["sku"],
      name: r["name"],
      price_cents: r["price_cents"],
      snippet: if(r["snippet"] in [nil, ""], do: nil, else: r["snippet"]),
      rank: Float.round(r["rank"], 4)
    }
  end
end
