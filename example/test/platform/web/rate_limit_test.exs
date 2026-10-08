defmodule Platform.Web.RateLimitTest do
  use Platform.ConnCase, async: false

  @key Platform.Web.RateLimit

  setup do
    old = Application.fetch_env!(:acme, @key)

    Application.put_env(:acme, @key,
      api: {3, 60_000},
      auth: {2, 60_000},
      trust_forwarded_for: false
    )

    Dandelion.RateLimit.reset()

    on_exit(fn ->
      Application.put_env(:acme, @key, old)
      Dandelion.RateLimit.reset()
    end)
  end

  test "the fourth request in a minute is a 429 with a retry-after", %{conn: conn} do
    for _ <- 1..3, do: assert(get(conn, "/api/anything").status == 404)

    limited = get(conn, "/api/anything")
    assert json_response(limited, 429)
    assert [seconds] = get_resp_header(limited, "retry-after")
    assert String.to_integer(seconds) in 1..61
  end

  test "logging in has its own, lower limit", %{conn: conn} do
    bad = %{"email" => "nobody@example.com", "password" => "wrong-password-1"}
    for _ <- 1..2, do: refute(post(conn, "/api/session", bad).status == 429)

    assert post(conn, "/api/session", bad).status == 429
    # the rest of the API has its own count
    refute get(conn, "/api/anything").status == 429
  end

  test "/health, /metrics and the payment webhook are never limited", %{conn: conn} do
    for _ <- 1..10 do
      assert get(conn, "/health").status == 200
      assert get(conn, "/metrics").status == 200
      refute post(conn, "/api/payments/webhook", %{}).status == 429
    end
  end

  test "clients are counted apart, by x-forwarded-for only when trusted", %{conn: conn} do
    Application.put_env(:acme, @key,
      api: {1, 60_000},
      auth: {1, 60_000},
      trust_forwarded_for: true
    )

    one = put_req_header(conn, "x-forwarded-for", "203.0.113.1, 10.0.0.1")
    two = put_req_header(conn, "x-forwarded-for", "203.0.113.2")

    assert get(one, "/api/anything").status == 404
    assert get(one, "/api/anything").status == 429
    assert get(two, "/api/anything").status == 404

    # not trusted: the header is ignored, so both are the same client
    Application.put_env(:acme, @key,
      api: {1, 60_000},
      auth: {1, 60_000},
      trust_forwarded_for: false
    )

    Dandelion.RateLimit.reset()
    assert get(one, "/api/anything").status == 404
    assert get(two, "/api/anything").status == 429
  end
end
