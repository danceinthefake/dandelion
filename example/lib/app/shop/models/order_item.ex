defmodule App.Shop.Models.OrderItem do
  @moduledoc "One line of an order. ≈ `type OrderItem struct`."
  use Ecto.Schema
  import Ecto.Changeset

  alias App.Shop.Models.Order

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]
  schema "order_items" do
    field :sku, :string
    field :quantity, :integer
    field :price_cents, :integer
    belongs_to :order, Order
    timestamps()
  end

  @type t :: %__MODULE__{}

  def changeset(item \\ %__MODULE__{}, attrs) do
    item
    |> cast(attrs, [:sku, :quantity, :price_cents])
    |> validate_required([:sku, :quantity, :price_cents])
    |> validate_length(:sku, min: 1, max: 64)
    # upper limits too: past the column's range, Postgres refuses the insert
    |> validate_number(:quantity, greater_than: 0, less_than_or_equal_to: 1_000_000)
    |> validate_number(:price_cents,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1_000_000_000_000
    )
  end
end
