defmodule Mix.Tasks.Dandelion.SyncTemplates do
  @shortdoc "Copies ../example into priv/templates (run before release)"
  @moduledoc """
  The generator's templates are the example service itself, copied into
  this package so hex can ship them. Run after changing `../example`:

      mix dandelion.sync_templates

  `test/templates_test.exs` fails while the two differ.
  """
  use Mix.Task

  @impl true
  def run(_args) do
    files = DandelionNew.Templates.example_files()

    # git ls-files lists nothing in a fresh checkout before `git add`;
    # never wipe the templates because of that.
    if files == [],
      do: Mix.raise("../example has no files tracked by git yet — `git add` them first")

    dest = Path.expand("priv/templates")
    File.rm_rf!(dest)

    for file <- files do
      target = Path.join(dest, file)
      File.mkdir_p!(Path.dirname(target))
      File.cp!(Path.join(DandelionNew.Templates.example_dir(), file), target)
    end

    write_formatter_opts()

    Mix.shell().info(
      "synced #{length(DandelionNew.Templates.example_files())} files into #{dest}"
    )
  end

  # Formatter options (no-parens rules from Phoenix / Ecto) for each Elixir
  # template, read from the example itself. The generator re-formats files
  # after renaming, because a name of another length moves line breaks.
  defp write_formatter_opts do
    code = """
    files = #{inspect(DandelionNew.Templates.example_files())}
    opts =
      for f <- files, String.ends_with?(f, [".ex", ".exs"]), into: %{} do
        {_fun, opts} = Mix.Tasks.Format.formatter_for_file(f)
        {f, Keyword.take(opts, [:locals_without_parens, :line_length, :force_do_end_blocks])}
      end
    File.write!(#{inspect(Path.expand("priv/formatter.exs"))}, inspect(opts, limit: :infinity, printable_limit: :infinity))
    """

    # The script writes the file itself: stdout may also carry the
    # example's dependency compile output on a fresh checkout.
    {_out, 0} =
      System.cmd("mix", ["run", "--no-start", "-e", code],
        cd: DandelionNew.Templates.example_dir()
      )
  end
end
