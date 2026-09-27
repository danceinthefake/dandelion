defmodule DandelionNew.Templates do
  @moduledoc """
  The example service, embedded at compile time from `priv/templates` — a
  copy of `../example` that `mix.exs` refreshes before every compile.
  """

  @root Path.expand("../../priv/templates", __DIR__)

  @paths Path.wildcard(Path.join(@root, "**/*"), match_dot: true) |> Enum.filter(&File.regular?/1)
  for path <- @paths, do: @external_resource(path)

  @files for path <- @paths, do: {Path.relative_to(path, @root), File.read!(path)}

  # Recompile when a template is added or removed (edits are covered by
  # @external_resource).
  @doc false
  def __mix_recompile__?,
    do:
      Path.wildcard(Path.join(@root, "**/*"), match_dot: true) |> Enum.filter(&File.regular?/1) !=
        @paths

  @formatter_file Path.expand("../../priv/formatter.exs", __DIR__)
  @external_resource @formatter_file
  @formatter if File.exists?(@formatter_file),
               do: elem(Code.eval_file(@formatter_file), 0),
               else: %{}

  @doc "`[{relative_path, contents}]` of every template file."
  def all, do: @files

  @doc """
  Formatter options for an Elixir template file, or nil: those of the
  deepest folder with a `.formatter.exs` (as `mix format` picks them).
  """
  def formatter_opts(file) do
    if Path.extname(file) in [".ex", ".exs"] do
      dir =
        @formatter
        |> Map.keys()
        |> Enum.filter(&(&1 == "." or String.starts_with?(file, &1 <> "/")))
        |> Enum.max_by(&String.length/1)

      @formatter[dir]
    end
  end

  # -- dev-time helpers (need the dandelion git checkout) ------------------------

  @doc false
  def example_dir, do: Path.expand("../../../example", __DIR__)
end
