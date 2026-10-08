# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :acme,
  ecto_repos: [Platform.Database.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :acme, Platform.Web.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: Platform.Web.ErrorJSON],
    layout: false
  ],
  pubsub_server: Platform.Broadcast

# Requests per client address and per minute (Platform.Web.RateLimit). Per node:
# behind a load balancer a cluster of N nodes allows about N times this. Logging
# in and registering get a far lower number: that is where passwords get guessed.
config :acme, Platform.Web.RateLimit,
  api: {300, :timer.minutes(1)},
  auth: {10, :timer.minutes(1)},
  trust_forwarded_for: false

# How long a node that was told to stop keeps serving while /health says
# "draining" (Dandelion.Drain), so the load balancer can move its traffic away.
config :acme, :drain_delay, 0

# Tracing is off until an OTLP endpoint is given (config/runtime.exs): no
# exporter means spans are made but go nowhere, and nothing tries to connect.
config :opentelemetry, traces_exporter: :none

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
