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
    # a query that has not answered in 5 s fails (the API answers 503), instead
    # of a request waiting on a database that hangs
    timeout: String.to_integer(System.get_env("DB_QUERY_TIMEOUT_MS") || "5000"),
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
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      thousand_island_options: [
        # at most this many connections open at once on this node; the rest
        # wait in the operating system's queue instead of exhausting memory
        num_connections: String.to_integer(System.get_env("MAX_CONNECTIONS") || "4096"),
        # a client that sends nothing for this long is disconnected (a
        # WebSocket sends pings, so it is not cut off)
        read_timeout: String.to_integer(System.get_env("READ_TIMEOUT_MS") || "60000"),
        # when the node stops: requests in flight get this long to finish
        shutdown_timeout: String.to_integer(System.get_env("SHUTDOWN_TIMEOUT_MS") || "20000")
      ]
    ],
    secret_key_base: secret_key_base

  # Slow down clients that ask too much (requests per minute, per node); see
  # Platform.Web.RateLimit. Behind a load balancer that overwrites x-forwarded-for
  # with the address it saw, TRUST_FORWARDED_FOR=1 makes that the client's address.
  config :acme, Platform.Web.RateLimit,
    api: {String.to_integer(System.get_env("RATE_LIMIT_API") || "300"), :timer.minutes(1)},
    auth: {String.to_integer(System.get_env("RATE_LIMIT_AUTH") || "10"), :timer.minutes(1)},
    trust_forwarded_for: System.get_env("TRUST_FORWARDED_FOR") in ["1", "true"]

  # @example-start
  # The address people reach the service at, for the links in emails (a reset, a confirmation).
  config :acme, :public_url, System.get_env("PUBLIC_URL")

  # @example-end

  # @example-start
  # Mail: SMTP_HOST sends through that server (SMTP_PORT default 587; SMTP_USERNAME and
  # SMTP_PASSWORD if it wants a login; SMTP_TLS is always, if_available (default) or never).
  # Without SMTP_HOST nothing is sent: each message is written to the log. MAIL_FROM_ADDRESS
  # and MAIL_FROM_NAME are the sender.
  config :acme,
    mail_from:
      {System.get_env("MAIL_FROM_NAME") || "Acme",
       System.get_env("MAIL_FROM_ADDRESS") || "no-reply@example.com"}

  if smtp_host = System.get_env("SMTP_HOST") do
    tls = String.to_existing_atom(System.get_env("SMTP_TLS") || "if_available")

    # (Swoosh refuses a username that is nil, so a login is only given when there is one)
    login =
      case System.get_env("SMTP_USERNAME") do
        nil -> [auth: :never]
        user -> [auth: :always, username: user, password: System.get_env("SMTP_PASSWORD")]
      end

    config :acme,
           Platform.Mailer,
           [
             adapter: Swoosh.Adapters.SMTP,
             relay: smtp_host,
             port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
             tls: tls,
             ssl: false,
             # our retries (Oban, the circuit) are the ones that count, not gen_smtp's sleeping ones
             retries: 0,
             no_mx_lookups: true
           ] ++ login

    config :acme, mail_host: smtp_host
  end

  config :acme,
    mail_backoff_seconds: String.to_integer(System.get_env("MAIL_BACKOFF_SECONDS") || "30"),
    mail_circuit_reset: String.to_integer(System.get_env("MAIL_CIRCUIT_RESET_MS") || "30000")

  # @example-end

  # @example-start
  # Uploaded files: a directory every node can see (a shared mount when there are
  # several nodes); UPLOAD_MAX_BYTES is the largest file accepted (up to 5 000 000).
  config :acme,
    uploads_dir: System.get_env("UPLOADS_DIR") || "/data/uploads",
    upload_max_bytes:
      min(String.to_integer(System.get_env("UPLOAD_MAX_BYTES") || "5000000"), 5_000_000)

  # ...or a bucket instead (any S3-compatible service: AWS S3, Google Cloud Storage's
  # interoperability endpoint, R2, Garage, SeaweedFS…): nothing has to be mounted on the nodes.
  if (bucket = System.get_env("S3_BUCKET")) not in [nil, ""] do
    config :acme,
      storage:
        {Dandelion.Storage.S3,
         [
           endpoint: System.fetch_env!("S3_ENDPOINT"),
           bucket: bucket,
           region: System.get_env("S3_REGION") || "us-east-1",
           access_key_id: System.fetch_env!("S3_ACCESS_KEY_ID"),
           secret_access_key: System.fetch_env!("S3_SECRET_ACCESS_KEY")
         ]}
  end

  # @example-end

  # @example-start
  # Webhooks we send: http and private addresses are refused unless allowed (a
  # private network's own receiver); WEBHOOK_BACKOFF_SECONDS is the wait before the
  # first retry, doubling each time up to an hour.
  config :acme,
    webhook_allow_http: System.get_env("WEBHOOK_ALLOW_HTTP") in ["1", "true"],
    webhook_allow_private: System.get_env("WEBHOOK_ALLOW_PRIVATE") in ["1", "true"],
    webhook_timeout: String.to_integer(System.get_env("WEBHOOK_TIMEOUT_MS") || "5000"),
    webhook_backoff_seconds: String.to_integer(System.get_env("WEBHOOK_BACKOFF_SECONDS") || "30"),
    webhook_circuit_reset:
      String.to_integer(System.get_env("WEBHOOK_CIRCUIT_RESET_MS") || "30000")

  # @example-end

  # On SIGTERM: say "draining" on /health for this long, then stop
  config :acme, :drain_delay, String.to_integer(System.get_env("DRAIN_DELAY_MS") || "5000")

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
