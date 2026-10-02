import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/acme start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :acme, Platform.Web.Endpoint, server: true
end

config :acme, Platform.Web.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Optional: with METRICS_TOKEN set, GET /metrics needs `Authorization: Bearer <token>`.
config :acme, :metrics_token, System.get_env("METRICS_TOKEN")

# Tracing: with OTEL_EXPORTER_OTLP_ENDPOINT set (e.g. http://jaeger:4318), spans
# are sent there over OTLP/HTTP, to Jaeger, Tempo, Honeycomb or any collector.
# The service name is OTEL_SERVICE_NAME (default: the app); each node says which
# it is through service.instance.id (rel/env.sh.eex).
if System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
  config :opentelemetry,
    traces_exporter: :otlp,
    resource: %{service: %{name: System.get_env("OTEL_SERVICE_NAME", "acme")}}

  config :opentelemetry_exporter, otlp_protocol: :http_protobuf
end

# ≈ envconfig: settings from environment variables, read at boot.
config :acme, App.Shop.Workers.ExpireUnpaidOrders,
  max_age_seconds: String.to_integer(System.get_env("UNPAID_ORDER_MAX_AGE_SECONDS", "3600"))

# A job left `executing` by a node that died is run again after this many
# seconds (Platform.Queue), checked every 5 s when this is set. The cluster
# proof sets it low.
if rescue_after = System.get_env("OBAN_RESCUE_AFTER_SECONDS") do
  config :acme, Oban,
    lifeline: [rescue_after: {String.to_integer(rescue_after), :second}, interval: 5_000]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Clustering needs a direct connection (not through PgBouncer); see Dandelion.Cluster.
  config :acme, Dandelion.Cluster, database_url: System.get_env("CLUSTER_DATABASE_URL")

  config :acme, Platform.Database.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :acme,
         :payment_webhook_token,
         System.get_env("PAYMENT_WEBHOOK_TOKEN") ||
           raise("""
           environment variable PAYMENT_WEBHOOK_TOKEN is missing.
           It is the secret the payment provider sends in the x-callback-token header.
           """)

  host = System.get_env("PHX_HOST") || "example.com"

  config :acme, Platform.Web.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :acme, Platform.Web.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :acme, Platform.Web.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
