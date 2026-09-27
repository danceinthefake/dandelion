defmodule Mix.Tasks.Dandelion.SyncFormatter do
  @shortdoc "Captures ../example's formatter rules into priv/formatter.exs"
  @moduledoc """
  The generator re-formats each Elixir file after renaming (a name of
  another length moves line breaks), with the example's own rules —
  including the no-parens forms Phoenix and Ecto export (`field :name`).
  Those come from the example's dependencies, so they're captured here,
  once per folder that has a `.formatter.exs`:

      mix dandelion.sync_formatter

  Run it when the example's `.formatter.exs` files or dependencies change.
  (The templates themselves are copied from ../example on every compile —
  see `mix.exs`.)
  """
  use Mix.Task

  alias DandelionNew.Templates

  @impl true
  def run(_args) do
    code = """
    {out, 0} = System.cmd("git", ["ls-files", "*.formatter.exs"])

    opts =
      for file <- String.split(out, "\\n", trim: true), into: %{} do
        dir = Path.dirname(file)
        {_fun, opts} = Mix.Tasks.Format.formatter_for_file(Path.join(dir, "x.ex"))
        {dir, Keyword.take(opts, [:locals_without_parens, :line_length, :force_do_end_blocks])}
      end

    File.write!(#{inspect(Path.expand("priv/formatter.exs"))}, inspect(opts, limit: :infinity, printable_limit: :infinity))
    """

    # The script writes the file itself: stdout may also carry the
    # example's dependency compile output on a fresh checkout.
    {_out, 0} = System.cmd("mix", ["run", "--no-start", "-e", code], cd: Templates.example_dir())
    Mix.shell().info("wrote priv/formatter.exs")
  end
end
