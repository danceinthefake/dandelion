defmodule Dandelion.MixProject do
  use Mix.Project

  @version "0.1.1"
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
        files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md),
        links: %{"GitHub" => @source_url}
      ],
      source_url: @source_url,
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"],
        # the tag the release workflow makes: dandelion-vX.Y.Z
        source_ref: "dandelion-v#{@version}",
        groups_for_modules: [
          Clustering: [Dandelion.Cluster, Dandelion.Cluster.Postgres],
          Cache: [Dandelion.Cache, Dandelion.Cache.Listener],
          "Jobs and events": [Dandelion.Queue, Dandelion.Queue.Ordered, Dandelion.PubSub],
          Database: [Dandelion.Migration]
        ]
      ]
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
      {:telemetry, "~> 1.0"},
      # optional: with it, a job continues the trace of what queued it (Dandelion.Trace)
      {:opentelemetry_api, "~> 1.4", optional: true},
      {:opentelemetry, "~> 1.5", only: :test},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false}
    ]
  end
end
