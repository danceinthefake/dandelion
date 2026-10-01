defmodule Platform.Web.MetricsHandlerTest do
  # not async: one test sets the app-wide token
  use Platform.ConnCase, async: false

  alias Dandelion.Cache
  alias Platform.Web.Telemetry

  test "GET /metrics is Prometheus text, with what the service has been doing", %{conn: conn} do
    get(conn, "/health")
    conn = get(conn, "/metrics")

    assert response(conn, 200) =~ "# TYPE http_request_duration histogram"
    assert [type] = get_resp_header(conn, "content-type")
    assert type =~ "text/plain"

    body = conn.resp_body
    assert body =~ ~s(http_request_duration_count{status="200"})
    assert body =~ "# TYPE platform_database_repo_query_total_time histogram"
    assert body =~ ~s(http_handler_duration_count{route="/health"})
  end

  test "the cluster size counts this node, and follows the connected ones" do
    Telemetry.cluster_size()
    assert Telemetry.scrape() =~ ~r/^platform_cluster_nodes_count 1$/m
  end

  test "cache hits and misses are counted by result", %{conn: conn} do
    key = {:metrics_test, System.unique_integer()}
    Cache.fetch(key, fn -> 1 end)
    Cache.fetch(key, fn -> 1 end)

    body = conn |> get("/metrics") |> response(200)
    assert body =~ ~s(dandelion_cache_fetches_total{result="miss"})
    assert body =~ ~s(dandelion_cache_fetches_total{result="hit"})
  end

  test "with METRICS_TOKEN set, the bearer token is needed", %{conn: conn} do
    Application.put_env(:acme, :metrics_token, "s3cret")
    on_exit(fn -> Application.delete_env(:acme, :metrics_token) end)

    assert conn |> get("/metrics") |> json_response(401)

    assert build_conn()
           |> put_req_header("authorization", "Bearer nope")
           |> get("/metrics")
           |> json_response(401)

    assert build_conn()
           |> put_req_header("authorization", "Bearer s3cret")
           |> get("/metrics")
           |> response(200)
  end
end
