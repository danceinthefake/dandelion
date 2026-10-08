defmodule Dandelion.Search do
  @moduledoc """
  Searching text in Postgres. ≈ an Elasticsearch / Algolia index for a catalogue-sized
  corpus — except that the "index" is the table itself, so there is nothing to keep in
  step.

      Dandelion.Search.search(Repo, "products", "gre tea",
        select: ["sku", "name", "price_cents"],
        snippet: "description",
        fuzzy: "name",
        limit: 10)
      #=> %{total: 3, match: :text, rows: [%{"sku" => "TEA-01", "name" => "Green tea",
      #=>   "price_cents" => 1500, "rank" => 0.91, "snippet" => "a fresh [[green]] …"}, …]}

  Set the table up with `Dandelion.Search.Migration.add_index/3`. That adds a `search`
  column that Postgres maintains itself (a generated column), so a row is searchable the
  moment it is committed, on every node, and a row that is deleted is gone from the next
  search: there is no second system whose copy can be late.

  **What the user types is data, never syntax.** `tsquery/1` keeps only the letters and
  digits of the input, so `& | ! ( ) : * ' " \\ < >` cannot reach the query language and
  no input can make it fail. Every word is a *prefix* and all words must match
  (`gre tea` finds `Green tea`; each keystroke narrows the results, which is what a search
  box wants). Accents are ignored (`cafe` finds `café`).

  **Ranking:** a match in a heavier column (the `:a` weight) beats a match in a lighter one,
  and a word that appears more often beats one that appears once (`ts_rank_cd`, normalised
  by document length); ties break by `:order` (default: the first selected column).

  **Typos:** with `fuzzy: "name"`, if the words match nothing and this is the first page, the
  search falls back to *similar words* (`pg_trgm`) in that column and says so: `match: :fuzzy`
  (`grean tea` finds `Green tea`). It is a fallback, not a fuzzy search: a query that finds
  something never mixes in guesses.

  **Snippets** (`snippet: "description"`) mark the matching words with `[[` and `]]`. They
  are *not* HTML: the text is whatever was stored, and it is the client's job to escape it
  before it shows `[[…]]` as bold. (Words only match in a snippet when they are spelled
  without accents the way the query is.)

  Limits: at most 50 rows a page and an offset of at most 1 000 (deep paging a search is a
  sign the user should type more). At most 10 words of at most 50 characters are used.

  Table and column names are given by your code, never by a user, and are checked to be
  plain identifiers; the text is always a bound parameter.
  """

  @max_limit 50
  @max_offset 1_000
  @max_words 10
  @max_word 50
  @identifier ~r/\A[a-z_][a-z0-9_]*\z/

  @type result :: %{
          total: non_neg_integer(),
          match: :text | :fuzzy | :none,
          rows: [%{optional(String.t()) => term()}]
        }

  @doc """
  A prefix-and-all-words tsquery from user input: `"Gre tea!"` becomes `"gre:* & tea:*"`.
  `nil` when there is no word in it (nothing to search for).
  """
  @spec tsquery(String.t()) :: String.t() | nil
  def tsquery(input) when is_binary(input) do
    terms =
      ~r/[\p{L}\p{N}]+/u
      |> Regex.scan(String.downcase(input))
      |> Enum.map(fn [word] -> String.slice(word, 0, @max_word) end)
      |> Enum.take(@max_words)

    if terms == [], do: nil, else: terms |> Enum.map(&"#{&1}:*") |> Enum.join(" & ")
  end

  @doc """
  Searches `table` for `text`. Options:

    * `:select` — the columns to return (required; plain names)
    * `:snippet` — a column to cut a highlighted fragment from
    * `:order` — the column that breaks ties in rank (default: the first of `:select`)
    * `:column` — the search column (default `"search"`)
    * `:fuzzy` — the column to compare words against when the words matched nothing (typos);
      without it there is no fallback. It needs the trigram index `add_index/3` makes for it
    * `:config` — the text search configuration the index was built with (default `"simple"`)
    * `:fallback` — `false` to turn the typo fallback off even with `:fuzzy`
    * `:limit` (default 10), `:offset` (default 0)
  """
  @spec search(module(), String.t(), String.t(), keyword()) :: result()
  def search(repo, table, text, opts) when is_binary(text) do
    select = Keyword.fetch!(opts, :select)
    check!([table | select])

    opts =
      opts
      |> Keyword.put_new(:order, hd(select))
      |> Keyword.put_new(:column, "search")
      |> Keyword.put_new(:config, "simple")

    check!([opts[:order], opts[:column], opts[:fuzzy], opts[:snippet]] |> Enum.reject(&is_nil/1))
    check!([opts[:config]])
    limit = opts |> Keyword.get(:limit, 10) |> max(1) |> min(@max_limit)
    offset = opts |> Keyword.get(:offset, 0) |> max(0) |> min(@max_offset)

    fallback? = opts[:fuzzy] != nil and Keyword.get(opts, :fallback, true)

    case tsquery(text) do
      nil ->
        %{total: 0, match: :none, rows: []}

      query ->
        case text_search(repo, table, query, select, opts, limit, offset) do
          %{total: 0} when offset == 0 and fallback? ->
            fuzzy_search(repo, table, text, select, opts, limit)

          result ->
            result
        end
    end
  end

  # -- inside ----------------------------------------------------------------------

  defp text_search(repo, table, query, select, opts, limit, offset) do
    config = opts[:config]
    snippet_sql = snippet_sql(opts[:snippet], config)

    sql = """
    SELECT #{columns(select)}, ts_rank_cd(t.#{opts[:column]}, q, 32) AS rank#{snippet_sql}, count(*) OVER() AS total
    FROM #{table} t, to_tsquery('#{config}', dandelion_unaccent($1)) q
    WHERE t.#{opts[:column]} @@ q
    ORDER BY rank DESC, t.#{opts[:order]}
    LIMIT $2 OFFSET $3
    """

    sql |> run(repo, [query, limit, offset]) |> shape(select, opts, :text)
  end

  # Words that are close to words in `:fuzzy`, when the words themselves matched nothing.
  # (word_similarity compares with the best-matching run of words, so one typo in a
  # three-word name still counts.)
  defp fuzzy_search(repo, table, text, select, opts, limit) do
    fuzzy = "dandelion_unaccent(lower(t.#{opts[:fuzzy]}))"

    sql = """
    SELECT #{columns(select)}, word_similarity(dandelion_unaccent(lower($1)), #{fuzzy}) AS rank, count(*) OVER() AS total
    FROM #{table} t
    WHERE dandelion_unaccent(lower($1)) <% #{fuzzy}
    ORDER BY rank DESC, t.#{opts[:order]}
    LIMIT $2
    """

    {:ok, result} =
      repo.transaction(fn ->
        repo.query!("SET LOCAL pg_trgm.word_similarity_threshold = 0.4")
        run(sql, repo, [String.slice(text, 0, 100), limit])
      end)

    shape(result, select, opts, :fuzzy)
  end

  defp snippet_sql(nil, _config), do: ""

  defp snippet_sql(column, config) do
    ", ts_headline('#{config}', coalesce(t.#{column}, ''), q, 'StartSel=[[, StopSel=]], MaxFragments=1, MaxWords=20, MinWords=5') AS snippet"
  end

  defp run(sql, repo, params), do: repo.query!(sql, params)

  defp shape(%{rows: [], columns: _}, _select, _opts, _kind),
    do: %{total: 0, match: :none, rows: []}

  defp shape(%{rows: rows, columns: columns}, select, _opts, kind) do
    maps = for row <- rows, do: columns |> Enum.zip(row) |> Map.new()
    total = maps |> hd() |> Map.fetch!("total")

    %{
      total: total,
      match: kind,
      rows: Enum.map(maps, &Map.drop(&1, ["total"])) |> Enum.map(&reshape(&1, select))
    }
  end

  # (columns come back in the order asked for; this only makes `rank` a float)
  defp reshape(row, _select), do: Map.update!(row, "rank", &(&1 * 1.0))

  defp columns(select), do: Enum.map_join(select, ", ", &"t.#{&1} AS #{&1}")

  defp check!(identifiers) do
    for name <- identifiers do
      unless is_binary(name) and name =~ @identifier,
        do: raise(ArgumentError, "not a plain table or column name: #{inspect(name)}")
    end

    :ok
  end
end
