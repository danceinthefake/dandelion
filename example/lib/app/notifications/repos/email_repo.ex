defmodule Platform.Database.Repos.EmailRepo do
  @moduledoc "Outgoing email queries, and nothing else."
  import Ecto.Query

  alias App.Notifications.Models.OutgoingEmail
  alias Platform.Database.Repo

  @doc """
  The email with this `dedupe_key`; makes it (`queued`) if there isn't one. Two callers
  with the same key get the same row.
  """
  @spec get_or_create(map()) :: OutgoingEmail.t()
  def get_or_create(%{dedupe_key: key} = attrs) do
    Repo.insert_all(OutgoingEmail, [Map.merge(attrs, now())],
      on_conflict: :nothing,
      conflict_target: :dedupe_key
    )

    Repo.get_by!(OutgoingEmail, dedupe_key: key)
  end

  @doc "Counts an attempt to send, before it is made."
  def attempt(%OutgoingEmail{id: id}) do
    from(e in OutgoingEmail, where: e.id == ^id, update: [inc: [attempts: 1]])
    |> Repo.update_all([])

    :ok
  end

  def mark_sent(%OutgoingEmail{id: id}) do
    from(e in OutgoingEmail, where: e.id == ^id)
    |> Repo.update_all(
      set: [
        status: "sent",
        sent_at: DateTime.utc_now(),
        last_error: nil,
        updated_at: DateTime.utc_now()
      ]
    )

    :ok
  end

  def mark_failed(%OutgoingEmail{id: id}, error) do
    from(e in OutgoingEmail, where: e.id == ^id)
    |> Repo.update_all(set: [status: "failed", last_error: error, updated_at: DateTime.utc_now()])

    :ok
  end

  def record_error(%OutgoingEmail{id: id}, error) do
    from(e in OutgoingEmail, where: e.id == ^id)
    |> Repo.update_all(set: [last_error: error, updated_at: DateTime.utc_now()])

    :ok
  end

  @doc "Newest first, optionally one status; `before` is an id."
  def list(status, before, limit) do
    OutgoingEmail
    |> then(fn q -> if status, do: where(q, status: ^status), else: q end)
    |> then(fn q -> if before, do: where(q, [e], e.id < ^before), else: q end)
    |> order_by(desc: :id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp now do
    now = DateTime.utc_now()
    %{inserted_at: now, updated_at: now}
  end
end
