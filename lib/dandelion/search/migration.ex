defmodule Dandelion.Search.Migration do
  @moduledoc """
  The database side of `Dandelion.Search`, called from your own migrations.

  Once per database (after the Oban migration, if you also use that):

      def up, do: Dandelion.Search.Migration.up()
      def down, do: Dandelion.Search.Migration.down()

  It turns on two extensions that ship with Postgres (`unaccent`, so `cafe` finds `café`,
  and `pg_trgm`, for typo-tolerant matching) and defines `dandelion_unaccent/1`, an
  immutable wrapper around `unaccent` (an index can only use immutable functions). Both
  extensions are "trusted": the owner of the database may create them without being a
  superuser.

  Then, for each table you want to search:

      def up do
        Dandelion.Search.Migration.add_index(:products, name: :a, description: :b)
      end

      def down, do: Dandelion.Search.Migration.drop_index(:products)

  `add_index/2` adds a `search` column (a `tsvector` that Postgres **keeps up to date
  itself**: a generated column, so it is always the text of the row, in the same
  transaction as the row), a GIN index on it, and a trigram index for the typo fallback
  on the column named by `:fuzzy` (default: the first column given). The columns are
  given with a weight, `:a` (the most important: a title) to `:d`; a match in a heavier
  column ranks higher.

  Options of `add_index/2`: `:config` (default `"simple"`: lower-cased words, no
  stemming, no stop words, which suits product names and works in any language; use
  `"english"`, `"indonesian"` … for stemming, and give `Dandelion.Search.search/4` the same
  `:config`), `:fuzzy`, and `:column` (the name of the search column, default `search`).
  Adding the column rewrites the table once.
  """
  import Ecto.Migration

  @doc "Turns on the extensions and defines `dandelion_unaccent/1`."
  def up do
    execute("CREATE EXTENSION IF NOT EXISTS unaccent")
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    execute("""
    CREATE OR REPLACE FUNCTION dandelion_unaccent(text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
    AS $$ SELECT public.unaccent('public.unaccent'::regdictionary, $1) $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS dandelion_unaccent(text)")
    execute("DROP EXTENSION IF EXISTS pg_trgm")
    execute("DROP EXTENSION IF EXISTS unaccent")
  end

  @weights [:a, :b, :c, :d]

  @doc "Makes `table` searchable. `columns` is a keyword list of column => weight."
  def add_index(table, columns, opts \\ []) when is_list(columns) and columns != [] do
    column = Keyword.get(opts, :column, :search)
    config = Keyword.get(opts, :config, "simple")
    {fuzzy, _} = hd(columns)
    fuzzy = Keyword.get(opts, :fuzzy, fuzzy)

    unless config =~ ~r/\A[a-z_]+\z/,
      do: raise(ArgumentError, "bad text search config: #{inspect(config)}")

    parts =
      for {name, weight} <- columns do
        unless weight in @weights,
          do: raise(ArgumentError, "weight must be :a, :b, :c or :d, got #{inspect(weight)}")

        "setweight(to_tsvector('#{config}', dandelion_unaccent(coalesce(#{name}, ''))), '#{String.upcase(to_string(weight))}')"
      end

    execute(
      "ALTER TABLE #{table} ADD COLUMN #{column} tsvector GENERATED ALWAYS AS (#{Enum.join(parts, " || ")}) STORED"
    )

    execute("CREATE INDEX #{table}_#{column}_index ON #{table} USING gin (#{column})")

    execute(
      "CREATE INDEX #{table}_#{fuzzy}_trgm_index ON #{table} USING gin (dandelion_unaccent(lower(#{fuzzy})) gin_trgm_ops)"
    )
  end

  @doc "Undoes `add_index/2`. Give the same `:column` and `:fuzzy` it was given."
  def drop_index(table, opts \\ []) do
    column = Keyword.get(opts, :column, :search)
    if fuzzy = opts[:fuzzy], do: execute("DROP INDEX IF EXISTS #{table}_#{fuzzy}_trgm_index")
    execute("DROP INDEX IF EXISTS #{table}_#{column}_index")
    execute("ALTER TABLE #{table} DROP COLUMN IF EXISTS #{column}")
  end
end
