defmodule Shop.Models.OrderItem do
  @moduledoc "One line of an order. ≈ `type OrderItem struct`."
  use Ecto.Schema
  import Ecto.Changeset

  alias Shop.Models.Order

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
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
  end
end
