defmodule App.Settings.Services.FlagService do
  @moduledoc """
  Settings and flags an admin changes while the app runs
  (`Dandelion.Flags`, from the library): saved in Postgres, cleared on every node.

  The flags the app reads:

    * `orders.enabled` (default `true`) — set it to `false` to pause new orders: they
      are answered 503 until it is turned back on. A kill switch for an incident or a
      migration; `OrderService.create/3` reads it.
  """
  alias App.Audit.Services.AuditService
  alias Dandelion.Flags

  def list, do: Flags.all()

  def put(key, value, viewer) do
    actor = AuditService.actor(viewer)

    case Flags.put(key, value,
           in_transaction: fn ->
             AuditService.record(actor, "flag.set", "flag:#{key}", %{value: value})
           end
         ) do
      {:ok, value} ->
        {:ok, %{key: key, value: value}}

      {:error, :invalid_key} ->
        {:error, {:invalid, "a flag key is lowercase letters, digits and . _ : - (up to 100)"}}

      {:error, :invalid_value} ->
        {:error, {:invalid, "a flag value must be JSON, up to 10 000 characters"}}
    end
  end

  def delete(key, viewer) do
    actor = AuditService.actor(viewer)

    case Flags.delete(key,
           in_transaction: fn -> AuditService.record(actor, "flag.deleted", "flag:#{key}") end
         ) do
      :ok -> :ok
      {:error, :invalid_key} -> {:error, :not_found}
    end
  end
end
