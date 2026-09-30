defmodule Dandelion.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/danceinthefake/dandelion"

  def project do
    [
      app: :dandelion,
      version: @version,
      elixir: "~> 1.18",
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

  defp deps do
    [
      {:cachex, "~> 4.1"},
      {:libcluster, "~> 3.5"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"}
    ]
  end
end
