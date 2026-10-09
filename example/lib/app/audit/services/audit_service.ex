defmodule App.Audit.Services.AuditService do
  @moduledoc """
  Who did what (`Dandelion.Audit`, from the library). Other domains call `record/4`
  **inside the transaction of the change** they are describing, so the change and its
  record are saved together or not at all; admins read it back at `/api/audit`.

  The actions recorded here:

      user.registered         session.created        session.rejected
      session.locked          password.reset_requested  password.reset
      email.confirmed
      product.price_changed   order.cancelled         order.paid
      order.refunded          orders.expired          flag.set  flag.deleted
      webhook.created         webhook.deleted         file.deleted

  Details hold what changed (`from`, `to`), never secrets: a webhook's secret and a
  password are not in the log.
  """
  alias Dandelion.Audit

  @type viewer :: %{id: integer()} | nil

  @doc "The actor string for a viewer: `user:5`, or `system` when nobody asked."
  def actor(nil), do: "system"
  def actor(%{id: id}), do: "user:#{id}"

  def record(actor, action, subject, details \\ %{}),
    do: Audit.record(actor, action, subject, details)

  @doc """
  Entries, newest first. `params` (strings, from a query): `actor`, `action` (exact, or a
  family ending in `.`), `subject`, `before` (an entry id), `limit`.
  """
  @spec list(map()) :: {:ok, [map()]} | {:error, {:invalid, String.t()}}
  def list(params) do
    with {:ok, before} <- int(params["before"], "before"),
         {:ok, limit} <- int(params["limit"], "limit") do
      opts =
        [
          actor: params["actor"],
          action: params["action"],
          subject: params["subject"],
          before: before,
          limit: limit || 50
        ]
        |> Enum.filter(fn {_key, value} -> value not in [nil, ""] end)

      {:ok, Audit.list(opts)}
    end
  end

  defp int(nil, _name), do: {:ok, nil}

  defp int(value, name) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, {:invalid, "#{name} must be a positive whole number"}}
    end
  end
end
