defmodule Dandelion.ClusterTest do
  use ExUnit.Case, async: true

  alias Dandelion.Cluster

  @opts [otp_app: :my_app, repo: nil]

  test "stays single when the node isn't distributed (mix phx.server, tests)" do
    refute Node.alive?()
    assert Cluster.topologies(@opts) == []
  end

  test "connects with the repo's settings, or a URL, on the app's own channel" do
    from_repo =
      Cluster.postgres(@opts,
        hostname: "db",
        port: 5432,
        username: "u",
        password: "p",
        database: "d"
      )

    assert from_repo[:hostname] == "db"
    assert from_repo[:channel_name] == "my_app_cluster"

    from_url = Cluster.postgres(@opts, url: "ecto://u:p@10.0.0.5:6432/orders")

    assert {from_url[:hostname], from_url[:port], from_url[:database]} ==
             {"10.0.0.5", 6432, "orders"}
  end

  test "the app's config can point past a pooler" do
    Application.put_env(:cluster_test_app, Cluster, database_url: "ecto://u:p@direct:5432/d")
    on_exit(fn -> Application.delete_env(:cluster_test_app, Cluster) end)

    conn =
      Cluster.postgres([otp_app: :cluster_test_app, repo: nil], url: "ecto://u:p@pooler:6432/d")

    assert {conn[:hostname], conn[:port]} == {"direct", 5432}
  end

  describe "URLs" do
    defp conn(url), do: Cluster.postgres(@opts, url: url)

    test "host, port, user, password and database, the port defaulting to 5432" do
      c = conn("ecto://u:p@db.internal/orders")

      assert {c[:hostname], c[:port], c[:username], c[:password], c[:database]} ==
               {"db.internal", 5432, "u", "p", "orders"}
    end

    test "percent-encoded characters in the password and database" do
      c = conn("ecto://u:p%40ss%3Aword@h:5433/my%20db")
      assert {c[:password], c[:database]} == {"p@ss:word", "my db"}
    end

    test "ssl=true, and no user at all" do
      assert conn("ecto://h/d?ssl=true")[:ssl] == true
      refute Keyword.has_key?(conn("ecto://h/d"), :ssl)
      refute Keyword.has_key?(conn("ecto://h/d"), :username)
    end
  end
end
