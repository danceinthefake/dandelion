import Config

# Plain-HTTP requests are redirected to HTTPS (and HSTS is set), trusting
# the load balancer's x-forwarded-proto header. /health is left alone for
# probes. If other services call this one over plain HTTP inside your network
# (e.g. http://acme:4000 in Kubernetes), they'd get a redirect: remove
# `force_ssl` here. It's read at compile time.
config :acme, Platform.Web.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      paths: ["/health"],
      hosts: ["localhost", "127.0.0.1"]
    ]
  ]

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
