defmodule App.Shop.Services.OrderService do
  @moduledoc """
  Order business rules. ≈ `service/orders.go`.

  No HTTP here (handlers do that) and no SQL (repos do that). Every function
  returns `{:ok, value}` or `{:error, reason}` — Elixir's `(value, err)`.
  """
  alias App.Shop.Models.Order
  alias App.Shop.Services.ProductService
  alias Platform.Database.Repo
  alias Platform.Database.Repos.OrderRepo
  alias Platform.PubSub

  @type error ::
          :not_found
          | {:invalid, String.t()}
          | {:conflict, String.t()}
          | Ecto.Changeset.t()

  @max_per_page 100
  # keeps OFFSET well inside Postgres's bigint
  @max_page 1_000_000

  @doc """
  Creates an order with its items and publishes `order.created` to its
  subscribers (`Platform.PubSub`), in one transaction: the order and the
  event are saved together, or neither is. Validation errors come back as a
  changeset.

  Each item is `%{"sku" => …, "quantity" => …}`; the **price comes from the
  products table** (through the cache), never from the request — a
  `"price_cents"` in an item is ignored. The price is copied onto the order
  line, so a later price change doesn't rewrite old orders. A SKU that isn't a
  product is `{:error, {:invalid, "unknown product: …"}}`.

  After the commit the event also goes out live on `Platform.Broadcast`, for
  whoever is watching right now (every node).
  """
  @spec create(map()) :: {:ok, Order.t()} | {:error, error()}
  def create(params) do
    with {:ok, params} <- price_items(params), do: insert_order(params)
  end

  defp insert_order(params) do
    result =
      Repo.transact(fn ->
        with {:ok, order} <- params |> Order.create_changeset() |> OrderRepo.insert() do
          PubSub.publish("order.created", %{
            "order_id" => order.id,
            "customer_email" => order.customer_email
          })

          {:ok, order}
        end
      end)

    with {:ok, order} <- result do
      Phoenix.PubSub.broadcast(Platform.Broadcast, "orders", {:order_created, order})
      {:ok, order}
    end
  end

  @doc "One order with its items."
  @spec get(integer()) :: {:ok, Order.t()} | {:error, error()}
  def get(id) do
    case OrderRepo.get(id) do
      nil -> {:error, :not_found}
      order -> {:ok, order}
    end
  end

  @doc """
  Orders, newest first. `params`: optional `"status"`, `"page"` (from 1),
  `"per_page"` (1..#{@max_per_page}, default 20).
  """
  @spec list(map()) ::
          {:ok, %{orders: [Order.t()], page: pos_integer(), per_page: pos_integer()}}
          | {:error, error()}
  def list(params) do
    with {:ok, status} <- status_param(params["status"]),
         {:ok, page} <- positive_int(params["page"], 1, @max_page, "page"),
         {:ok, per_page} <- positive_int(params["per_page"], 20, @max_per_page, "per_page") do
      orders = OrderRepo.list(%{status: status, page: page, per_page: per_page})
      {:ok, %{orders: orders, page: page, per_page: per_page}}
    end
  end

  @doc """
  Cancels an order. Pending and paid orders can be cancelled; shipped ones
  can't. The row is locked while deciding, so two cancels (or a cancel and
  a "mark shipped") can't race. ≈ a Go `tx` with `SELECT … FOR UPDATE`.
  """
  @spec cancel(integer()) :: {:ok, Order.t()} | {:error, error()}
  def cancel(id) do
    Repo.transact(fn ->
      with {:ok, order} <- locked(id),
           :ok <- cancellable(order),
           {:ok, order} <- OrderRepo.update_status(order, "cancelled") do
        {:ok, Repo.preload(order, :items)}
      end
    end)
  end

  @doc """
  An order was paid. Safe to repeat. Only a pending order can be paid.
  Used by `App.Shop.Workers.ProcessPaymentEvent`.
  """
  @spec mark_paid(integer()) :: {:ok, Order.t()} | {:error, error()}
  def mark_paid(id), do: transition(id, "paid", from: ["pending"])

  @doc """
  An order was refunded. Safe to repeat. A paid or shipped order can be
  refunded.
  """
  @spec mark_refunded(integer()) :: {:ok, Order.t()} | {:error, error()}
  def mark_refunded(id), do: transition(id, "refunded", from: ["paid", "shipped"])

  @doc """
  Cancels pending orders created more than `max_age_seconds` ago. Returns
  how many were cancelled. Used by `App.Shop.Workers.ExpireUnpaidOrders`.

  One `UPDATE … WHERE status = 'pending'`, not "list, then cancel each": an
  order paid in between would be cancelled by the second step. Postgres
  checks the `WHERE` again on each row as it locks it, so a paid order is
  never touched.
  """
  @spec expire_unpaid(pos_integer()) :: non_neg_integer()
  def expire_unpaid(max_age_seconds) do
    DateTime.utc_now()
    |> DateTime.add(-max_age_seconds, :second)
    |> OrderRepo.cancel_pending_before()
  end

  # -- helpers -----------------------------------------------------------------

  # Puts each item's price from its product. Items that aren't `%{"sku" => text}`
  # are left alone: the changeset reports what's wrong with them.
  defp price_items(%{"items" => items} = params) when is_list(items) do
    products =
      for %{"sku" => sku} <- items, is_binary(sku), uniq: true, into: %{} do
        {sku, ProductService.get(sku)}
      end

    case for({sku, {:error, :not_found}} <- products, do: sku) do
      [] ->
        {:ok, %{params | "items" => Enum.map(items, &price_item(&1, products))}}

      unknown ->
        {:error, {:invalid, "unknown product: #{unknown |> Enum.sort() |> Enum.join(", ")}"}}
    end
  end

  defp price_items(params), do: {:ok, params}

  defp price_item(%{"sku" => sku} = item, products) when is_binary(sku) do
    {:ok, product} = Map.fetch!(products, sku)
    Map.put(item, "price_cents", product.price_cents)
  end

  defp price_item(item, _products), do: item

  # Moves the order to `to` if it is in one of `from` (or already there),
  # with the row locked, like `cancel/1`.
  defp transition(id, to, from: from) do
    Repo.transact(fn ->
      with {:ok, order} <- locked(id), do: move(order, to, from)
    end)
  end

  defp move(%Order{status: to} = order, to, _from), do: {:ok, order}

  defp move(%Order{status: status} = order, to, from) when is_list(from) do
    if status in from do
      with {:ok, order} <- OrderRepo.update_status(order, to) do
        {:ok, Repo.preload(order, :items)}
      end
    else
      {:error, {:conflict, "a #{status} order can't become #{to}"}}
    end
  end

  defp locked(id) do
    case OrderRepo.lock_for_update(id) do
      nil -> {:error, :not_found}
      order -> {:ok, order}
    end
  end

  defp cancellable(%Order{status: status}) when status in ["pending", "paid"], do: :ok

  defp cancellable(%Order{status: "shipped"}),
    do: {:error, {:conflict, "a shipped order can't be cancelled"}}

  defp cancellable(%Order{status: "cancelled"}),
    do: {:error, {:conflict, "the order is already cancelled"}}

  defp cancellable(%Order{status: "refunded"}),
    do: {:error, {:conflict, "a refunded order can't be cancelled"}}

  defp status_param(nil), do: {:ok, nil}

  defp status_param(status) do
    if status in Order.statuses(),
      do: {:ok, status},
      else: {:error, {:invalid, "status must be one of: #{Enum.join(Order.statuses(), ", ")}"}}
  end

  defp positive_int(nil, default, _max, _name), do: {:ok, default}

  # Query parameters are strings — or maps / lists (`?page[x]=1`), which are
  # just as invalid.
  defp positive_int(value, _default, max, name) do
    case is_binary(value) and Integer.parse(value) do
      {n, ""} when n in 1..max//1 -> {:ok, n}
      _ -> {:error, {:invalid, "#{name} must be a whole number from 1 to #{max}"}}
    end
  end
end
