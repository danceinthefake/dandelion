defmodule App.Shop.Models.Product do
  @moduledoc "A product and its price. ≈ `type Product struct` in `model/product.go`."
  use Ecto.Schema
  import Ecto.Changeset

  @max_price 9_223_372_036_854_775_807

  @primary_key {:sku, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  schema "products" do
    field :name, :string
    field :price_cents, :integer
    timestamps(inserted_at: false)
  end

  @type t :: %__MODULE__{}

  @doc """
  Validates a new price. The request must carry one (the product already has
  a price, so `validate_required` alone would accept an empty request).
  """
  def price_changeset(product, attrs) do
    product
    |> cast(attrs, [:price_cents])
    |> require_in_request(:price_cents)
    |> validate_number(:price_cents,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: @max_price
    )
  end

  defp require_in_request(changeset, field) do
    if changeset.params[Atom.to_string(field)] in [nil, ""],
      do: add_error(changeset, field, "can't be blank"),
      else: changeset
  end
end
