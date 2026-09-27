defmodule Shop.Models.Order do
  @moduledoc """
  An order. ≈ `type Order struct` in `model/order.go`, plus its validation.

  The schema describes the table; `create_changeset/2` validates input for a
  new order — a changeset is "the changes we want, and what's wrong with
  them", checked before anything touches the database.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Shop.Models.OrderItem

  @statuses ~w(pending paid shipped cancelled)

  @timestamps_opts [type: :utc_datetime_usec]
  schema "orders" do
    field :customer_email, :string
    field :status, :string, default: "pending"
    field :total_cents, :integer
    has_many :items, OrderItem
    timestamps()
  end

  @type t :: %__MODULE__{}

  def statuses, do: @statuses

  @doc """
  Validates a new order and its items together, and computes the total.
  Errors in any item show up under `items` in the result.
  """
  def create_changeset(order \\ %__MODULE__{}, attrs) do
    order
    |> cast(attrs, [:customer_email])
    |> validate_required([:customer_email])
    |> validate_format(:customer_email, ~r/\A[^@\s]+@[^@\s]+\z/,
      message: "must be an email address"
    )
    |> validate_length(:customer_email, max: 254)
    |> cast_assoc(:items, with: &OrderItem.changeset/2, required: true)
    |> put_total()
  end

  # total = Σ quantity × price, once every item is valid
  defp put_total(%{valid?: false} = changeset), do: changeset

  defp put_total(changeset) do
    total =
      changeset
      |> get_assoc(:items, :struct)
      |> Enum.reduce(0, fn item, sum -> sum + item.quantity * item.price_cents end)

    put_change(changeset, :total_cents, total)
  end
end
