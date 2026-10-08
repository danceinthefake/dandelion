import Config

# Jobs are only run by tests themselves (Oban.Testing), no queues or cron.
config :acme, Oban, testing: :manual

# tests log in over and over from one address
config :acme, Platform.Web.RateLimit,
  api: {100_000, :timer.minutes(1)},
  auth: {100_000, :timer.minutes(1)},
  trust_forwarded_for: false

# @example-start
# webhooks: no real network. Requests go to Req.Test stubs, hosts are not resolved.
config :acme,
  webhook_allow_private: true,
  webhook_req_options: [plug: {Req.Test, App.Webhooks}],
  webhook_circuit_reset: 100

# @example-end

config :acme, :payment_webhook_token, "test-token"

# fast password hashing in tests (a real hash takes about a quarter of a second)
config :acme, App.Accounts.Services.Password, iterations: 1_000

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :acme, Platform.Database.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 55432,
  database: "acme_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :acme, Platform.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Kr2MT+5ZDIY2schFHvXzlxbB/m3mOU4be7AqgOWtJtSBxg/OGNUxZtIbZjhc6fob",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
