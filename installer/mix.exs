defmodule DandelionNew.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :dandelion_new,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: false,
      deps: [],
      description: "mix dandelion.new — an Elixir service laid out the way a Go service is",
      package: [
        licenses: ["MIT"],
        files: ~w(lib priv mix.exs README.md),
        links: %{"GitHub" => "https://github.com/danceinthefake/dandelion"}
      ]
    ]
  end

  def application, do: [extra_applications: [:eex, :crypto]]
end
