defmodule Platform.Database.Repos.OrderRepo do
  @moduledoc """
  Order queries — and nothing else. ≈ `repo/orders.go`.

  No business rules here: the service decides *what* happens, the repo only
  knows *how* to read and write it.
  """
  import Ecto.Query

  alias App.Shop.Models.Order
  alias Platform.Database.Repo

  # Whose orders a query may see: `:all`, or `{:user, id}` for one customer's.
  @type scope :: :all | {:user, integer()}

  @doc "An order with its items, or nil. Within `scope`: another customer's is nil."
  @spec get(integer(), scope()) :: Order.t() | nil
  def get(id, scope \\ :all) do
    Order |> where(id: ^id) |> scoped(scope) |> Repo.one() |> Repo.preload(:items)
  end

  @doc "Orders newest first, optionally by status, one page at a time, within `scope`."
  @spec list(%{
          required(:page) => pos_integer(),
          required(:per_page) => pos_integer(),
          required(:status) => String.t() | nil,
          optional(:scope) => scope()
        }) :: [Order.t()]
  def list(%{status: status, page: page, per_page: per_page} = query) do
    Order
    |> scoped(Map.get(query, :scope, :all))
    |> then(fn q -> if status, do: where(q, status: ^status), else: q end)
    |> order_by(desc: :inserted_at, desc: :id)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
    |> Repo.preload(:items)
  end

  @doc "Locks the order row until the transaction ends. ≈ SELECT … FOR UPDATE."
  @spec lock_for_update(integer(), scope()) :: Order.t() | nil
  def lock_for_update(id, scope \\ :all) do
    Order |> where(id: ^id) |> scoped(scope) |> lock("FOR UPDATE") |> Repo.one()
  end

  @doc "Inserts an order with its items (one transaction, done by Ecto)."
  def insert(%Ecto.Changeset{} = changeset), do: Repo.insert(changeset)

  @doc "Sets the order's status."
  def update_status(%Order{} = order, status) do
    order |> Ecto.Changeset.change(status: status) |> Repo.update()
  end

  @doc "Cancels pending orders created before `cutoff`; returns how many."
  @spec cancel_pending_before(DateTime.t()) :: non_neg_integer()
  def cancel_pending_before(cutoff) do
    {count, _} =
      Order
      |> where([o], o.status == "pending" and o.inserted_at < ^cutoff)
      |> Repo.update_all(set: [status: "cancelled", updated_at: DateTime.utc_now()])

    count
  end

  defp scoped(query, :all), do: query
  defp scoped(query, {:user, user_id}), do: where(query, user_id: ^user_id)
end
