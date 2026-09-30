defmodule Dandelion.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/danceinthefake/dandelion"

  def project do
    [
      app: :dandelion,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: [test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]],
      deps: deps(),
      description:
        "The cloud pieces of a dandelion service: clustering, cache, ordered queue, durable pub/sub",
      package: [
        licenses: ["MIT"],
        files: ~w(lib mix.exs README.md LICENSE),
        links: %{"GitHub" => @source_url}
      ],
      source_url: @source_url
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli, do: [preferred_envs: [test: :test]]

  defp deps do
    [
      {:cachex, "~> 4.1"},
      {:libcluster, "~> 3.5"},
      {:oban, "~> 2.24"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"}
    ]
  end
end
