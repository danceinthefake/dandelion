defmodule App.Shop.Models.Product do
  @moduledoc "A product and its price. ≈ `type Product struct` in `model/product.go`."
  use Ecto.Schema
  import Ecto.Changeset

  # the same ceiling an order line has (OrderItem)
  @max_price 1_000_000_000_000

  @primary_key {:sku, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  schema "products" do
    field :name, :string
    field :price_cents, :integer
    # what the search looks in, besides the name
    field :description, :string
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

  @doc "A new product: sku (letters, digits, `-` `_`), name, optional description, price."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:sku, :name, :description, :price_cents])
    |> validate_required([:sku, :name, :price_cents])
    |> validate_format(:sku, ~r/\A[A-Za-z0-9_-]{1,64}\z/,
      message: "can only have letters, digits, - and _ (up to 64)"
    )
    |> details_validations()
    |> validate_number(:price_cents,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: @max_price
    )
    |> unique_constraint(:sku, name: :products_pkey)
  end

  @doc "New name and/or description for a product (at least one must be in the request)."
  def details_changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :description])
    |> details_validations()
    |> require_one_of([:name, :description])
  end

  defp details_validations(changeset) do
    changeset
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:description, max: 5_000)
  end

  defp require_one_of(changeset, fields) do
    if Enum.any?(fields, &(changeset.params[Atom.to_string(&1)] not in [nil])),
      do: changeset,
      else: add_error(changeset, hd(fields), "send a name and/or a description")
  end

  defp require_in_request(changeset, field) do
    if changeset.params[Atom.to_string(field)] in [nil, ""],
      do: add_error(changeset, field, "can't be blank"),
      else: changeset
  end
end
