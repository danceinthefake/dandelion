defmodule Dandelion.Audit do
  @moduledoc """
  A record of who did what, kept in Postgres. ≈ CloudTrail / an audit table you would
  otherwise write by hand — and then forget to write in one place.

  Start it with your repo, and add the table with a migration (after the Oban one):

      {Dandelion.Audit, repo: MyApp.Repo}

      def up, do: Dandelion.Audit.Migration.up()
      def down, do: Dandelion.Audit.Migration.down()

  Record an entry **inside the transaction that makes the change**, so the change and
  its record are saved together or not at all — the same rule as `Dandelion.PubSub`:

      Repo.transact(fn ->
        with {:ok, product} <- Repo.update(changeset) do
          Dandelion.Audit.record("user:5", "product.price_changed", "product:TEA-01",
            %{from: 1500, to: 1600})
          {:ok, product}
        end
      end)

    * **actor** — who: `"user:5"`, `"system:payment_webhook"`, `"anonymous"`. A string
      you choose; the library does not know your users.
    * **action** — what: lowercase words and dots, `"order.cancelled"`. Filter by prefix
      (`"order."`) to see a family.
    * **subject** — what it happened to: `"order:42"`.
    * **details** — anything JSON can hold, up to 10 000 bytes (what changed, from and
      to). **Never put secrets or whole request bodies here**: the log is kept.

  The request id (`Logger.metadata()[:request_id]`, set by `Plug.RequestId`) is stored
  with each entry, so an entry can be matched to the log lines and the trace of the
  request that made it.

  **Append-only.** The table refuses `UPDATE`, `DELETE` and `TRUNCATE` (a trigger): a bug
  in the app, or a handler that tries to "fix" history, fails instead of rewriting it.
  Old entries are removed on purpose with `prune/1` (retention), which is the only way. A
  database superuser can still disable the trigger — this makes the log hard to change
  by accident, not proof against someone who owns the database. It is not hash-chained.

  `list/1` reads it back, newest first, a page at a time (`before:` is the id of the last
  entry of the previous page).
  """

  @action_format ~r/\A[a-z0-9_.]{1,100}\z/
  @max_text 200
  @max_details_bytes 10_000
  @max_page 200

  @doc false
  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  @doc false
  # Only remembers the repo; there is nothing to supervise.
  def start_link(opts) do
    :persistent_term.put({__MODULE__, :repo}, Keyword.fetch!(opts, :repo))
    :ignore
  end

  @doc """
  Adds an entry. Call it inside the transaction of the change it describes. Raises
  `ArgumentError` for a malformed entry (that is a bug in the caller, not a runtime
  condition).
  """
  @spec record(String.t(), String.t(), String.t(), map()) :: :ok
  def record(actor, action, subject, details \\ %{}) do
    check!(actor, subject)

    unless is_binary(action) and action =~ @action_format,
      do: raise(ArgumentError, "bad audit action: #{inspect(action)}")

    case Jason.encode(details) do
      {:ok, json} when byte_size(json) <= @max_details_bytes ->
        :ok

      _ ->
        raise ArgumentError, "audit details must be JSON of at most #{@max_details_bytes} bytes"
    end

    repo().query!(
      "INSERT INTO dandelion_audit (at, actor, action, subject, details, request_id) VALUES (clock_timestamp(), $1, $2, $3, $4, $5)",
      [actor, action, subject, details, Keyword.get(Logger.metadata(), :request_id)]
    )

    :ok
  end

  @doc """
  Entries, newest first. Options: `:actor` and `:subject` (exact), `:action` (exact, or a
  prefix ending in `.` such as `"order."`), `:before` (an id: entries older than it),
  `:limit` (default 50, at most #{@max_page}).
  """
  @spec list(keyword()) :: [map()]
  def list(opts \\ []) do
    {where, params} =
      Enum.reduce([:actor, :subject, :action, :before], {[], []}, fn key, {w, p} ->
        case Keyword.get(opts, key) do
          nil -> {w, p}
          value -> {w ++ [condition(key, length(p) + 1)], p ++ [param(key, value)]}
        end
      end)

    limit = opts |> Keyword.get(:limit, 50) |> max(1) |> min(@max_page)
    where_sql = if where == [], do: "", else: "WHERE " <> Enum.join(where, " AND ")

    %{rows: rows} =
      repo().query!(
        "SELECT id, at, actor, action, subject, details, request_id FROM dandelion_audit #{where_sql} ORDER BY id DESC LIMIT #{limit}",
        params
      )

    for [id, at, actor, action, subject, details, request_id] <- rows do
      %{
        id: id,
        at: DateTime.from_naive!(at, "Etc/UTC"),
        actor: actor,
        action: action,
        subject: subject,
        details: details,
        request_id: request_id
      }
    end
  end

  @doc """
  Removes entries older than `datetime` (retention). Returns how many. The only way the
  table lets anything be deleted.
  """
  @spec prune(DateTime.t()) :: non_neg_integer()
  def prune(%DateTime{} = datetime) do
    {:ok, count} =
      repo().transaction(fn ->
        repo().query!("SET LOCAL dandelion.audit_prune = 'on'")
        %{num_rows: n} = repo().query!("DELETE FROM dandelion_audit WHERE at < $1", [datetime])
        # (inside a larger transaction SET LOCAL would otherwise last until its end)
        repo().query!("SET LOCAL dandelion.audit_prune = 'off'")
        n
      end)

    count
  end

  # -- inside ----------------------------------------------------------------------

  defp condition(:action, n),
    do: "(action = $#{n} OR (right($#{n}, 1) = '.' AND left(action, length($#{n})) = $#{n}))"

  defp condition(:before, n), do: "id < $#{n}"
  defp condition(key, n), do: "#{key} = $#{n}"

  defp param(_key, value), do: value

  defp check!(actor, subject) do
    for {name, value} <- [actor: actor, subject: subject] do
      unless is_binary(value) and value != "" and String.length(value) <= @max_text,
        do: raise(ArgumentError, "bad audit #{name}: #{inspect(value)}")
    end
  end

  defp repo, do: :persistent_term.get({__MODULE__, :repo})
end
