import Config

# Only the library's own tests use a database; a project that depends on
# dandelion brings its own repo.
if config_env() == :test do
  config :dandelion, ecto_repos: [Dandelion.TestRepo]

  config :dandelion, Dandelion.TestRepo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    port: 55432,
    database: "dandelion_test",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10,
    priv: "priv/test_repo"

  config :opentelemetry, traces_exporter: :none

  config :logger, level: :warning
end
