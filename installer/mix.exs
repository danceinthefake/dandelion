defmodule DandelionNew.MixProject do
  use Mix.Project

  @version "0.1.1"

  def project do
    [
      app: :dandelion_new,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: false,
      deps: deps(),
      description: "mix dandelion.new — an Elixir service laid out the way a Go service is",
      aliases: aliases(),
      package: [
        licenses: ["MIT"],
        files: ~w(lib priv mix.exs README.md LICENSE),
        links: %{"GitHub" => "https://github.com/danceinthefake/dandelion"}
      ],
      source_url: "https://github.com/danceinthefake/dandelion",
      docs: [
        main: "readme",
        extras: ["README.md"],
        source_ref: "v#{@version}",
        # the generator lives in installer/ of the repository
        source_url_pattern:
          "https://github.com/danceinthefake/dandelion/blob/v#{@version}/installer/%{path}#L%{line}"
      ]
    ]
  end

  # The generator has no runtime dependencies (the generated project has its own).
  defp deps, do: [{:ex_doc, "~> 0.40.4", only: :dev, runtime: false}]

  def application, do: [extra_applications: [:eex, :crypto]]

  # The templates are ../example itself, copied into priv/templates (not
  # committed) before every compile and package build. Only in a dandelion
  # checkout: a hex install already has priv/templates in the package.
  defp aliases do
    [
      compile: [&copy_example/1, "compile"],
      "archive.build": [&copy_example/1, "archive.build"],
      "hex.build": [&copy_example/1, "hex.build"],
      "hex.publish": [&copy_example/1, "hex.publish"]
    ]
  end

  @example Path.expand("../example", __DIR__)
  @templates Path.expand("priv/templates", __DIR__)

  defp copy_example(_args) do
    if File.dir?(@example) do
      # tracked files only (no deps, _build, secrets), minus the example's
      # own README — generated projects get their own
      {out, 0} = System.cmd("git", ["ls-files"], cd: @example)
      files = out |> String.split("\n", trim: true) |> Enum.reject(&(&1 == "README.md"))

      File.rm_rf!(@templates)

      for file <- files do
        target = Path.join(@templates, file)
        File.mkdir_p!(Path.dirname(target))
        File.cp!(Path.join(@example, file), target)
      end
    end
  end
end
