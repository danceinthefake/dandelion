defmodule Platform.Web.RateLimit do
  @moduledoc """
  Slows a client that asks too much: 429 with a `retry-after`. ≈ a Go
  `httprate.LimitByIP` middleware. The counting is `Dandelion.RateLimit`
  (in memory, per node: a cluster of three allows about three times the
  limit — see its docs).

  Two buckets, per client address, on `/api` only (`/health`, `/metrics` and the
  payment webhook, which has its own token, are never limited):

    * `:auth` — logging in, registering, asking for and using password and address links. Few, because this is where a
      password guesser knocks.
    * `:api` — everything else.

  Limits are `{requests, per_milliseconds}` in
  `config :acme, Platform.Web.RateLimit` (see `config/config.exs`;
  `config/runtime.exs` reads `RATE_LIMIT_API` and `RATE_LIMIT_AUTH`, requests per
  minute). The client address is the connection's, or — behind a load balancer
  that *overwrites* `x-forwarded-for` with the address it saw — the header's:
  set `TRUST_FORWARDED_FOR=1` only then, or a client can pick its own address.
  """
  @behaviour Plug

  import Plug.Conn

  alias Dandelion.RateLimit

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{path_info: ["api", "payments", "webhook" | _]} = conn, _opts), do: conn

  def call(%{path_info: ["api" | _]} = conn, _opts) do
    {limit, window} = limit(bucket(conn))

    case RateLimit.hit({bucket(conn), client(conn)}, limit, window) do
      {:allow, _count} -> conn
      {:deny, wait} -> too_many(conn, wait)
    end
  end

  def call(conn, _opts), do: conn

  defp bucket(%{method: "POST", path_info: ["api", name]}) when name in ["session", "users"],
    do: :auth

  # asking for a link, using one, confirming an address: all things to guess at, or to make mail with
  defp bucket(%{method: "POST", path_info: ["api", "password", _]}), do: :auth
  defp bucket(%{method: "POST", path_info: ["api", "email", _]}), do: :auth

  defp bucket(_conn), do: :api

  defp limit(bucket), do: Keyword.fetch!(config(), bucket)

  defp client(conn) do
    forwarded = get_req_header(conn, "x-forwarded-for")

    if config()[:trust_forwarded_for] and forwarded != [] do
      forwarded |> hd() |> String.split(",") |> hd() |> String.trim()
    else
      conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp too_many(conn, wait) do
    conn
    |> put_resp_header("retry-after", wait |> div(1000) |> Kernel.+(1) |> to_string())
    |> put_resp_content_type("application/json")
    |> send_resp(429, ~s({"errors":{"detail":"Too Many Requests"}}))
    |> halt()
  end

  defp config, do: Application.fetch_env!(:acme, __MODULE__)
end
