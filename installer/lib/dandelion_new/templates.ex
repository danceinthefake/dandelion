defmodule DandelionNew.Templates do
  @moduledoc """
  The example service, embedded at compile time from `priv/templates`
  (a copy of `../example`, kept in sync by `mix dandelion.sync_templates`).
  """

  @root Path.expand("../../priv/templates", __DIR__)

  @files (for path <- Path.wildcard(Path.join(@root, "**/*"), match_dot: true),
              File.regular?(path) do
            @external_resource path
            {Path.relative_to(path, @root), File.read!(path)}
          end)

  @formatter_file Path.expand("../../priv/formatter.exs", __DIR__)
  @external_resource @formatter_file
  @formatter if File.exists?(@formatter_file),
               do: elem(Code.eval_file(@formatter_file), 0),
               else: %{}

  @doc "`[{relative_path, contents}]` of every template file."
  def all, do: @files

  @doc "Formatter options for an Elixir template file, or nil."
  def formatter_opts(file), do: Map.get(@formatter, file)

  # -- dev-time helpers (need the dandelion git checkout) ------------------------

  @doc false
  def example_dir, do: Path.expand("../../../example", __DIR__)

  @doc false
  # Tracked files of ../example, minus its own README (generated projects get
  # their own).
  def example_files do
    {out, 0} = System.cmd("git", ["ls-files"], cd: example_dir())
    out |> String.split("\n", trim: true) |> Enum.reject(&(&1 == "README.md"))
  end
end
