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

# Webhooks we send (App.Webhooks): receivers must be https and public; the wait before
# the first retry doubles each time (up to an hour); the circuit for a receiver that
# keeps failing stays open this long before one request is tried again.
# @example-start
# Mail (Platform.Mailer, App.Notifications): written to the log until config/runtime.exs is
# given an SMTP server. Swoosh needs no HTTP client for SMTP. A failed send is retried with a
# wait that doubles from this many seconds; the circuit for a mail server that keeps failing
# stays open this long (ms) before one message is tried again.
config :swoosh, :api_client, false
config :acme, Platform.Mailer, adapter: Swoosh.Adapters.Logger, level: :info

config :acme,
  mail_from: {"Acme", "no-reply@example.com"},
  mail_backoff_seconds: 30,
  mail_circuit_reset: 30_000

# @example-end

# @example-start
# Uploaded files (App.Files): one directory, which with several nodes must be a shared
# mount (Dandelion.Storage), and the largest file accepted in bytes. The endpoint reads
# a multipart body of up to 6 000 000 bytes (lib/platform/web/endpoint.ex).
config :acme,
  uploads_dir: "tmp/uploads",
  upload_max_bytes: 5_000_000

# @example-end

# @example-start
config :acme,
  webhook_allow_http: false,
  webhook_allow_private: false,
  webhook_timeout: 5_000,
  webhook_backoff_seconds: 30,
  webhook_circuit_reset: 30_000

# @example-end

# lib/platform/web/database_unavailable.ex maps Postgrex.Error itself
config :phoenix_ecto, exclude_ecto_exceptions_from_plug: [Postgrex.Error]

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
