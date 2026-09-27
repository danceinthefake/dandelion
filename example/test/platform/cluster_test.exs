defmodule Platform.ClusterTest do
  use ExUnit.Case, async: true

  alias Platform.Cluster

  test "stays single when the node isn't distributed (mix phx.server, tests)" do
    refute Node.alive?()
    assert Cluster.topologies() == []
  end

  test "connects with the repo's settings, or a URL, on its own channel" do
    from_repo =
      Cluster.postgres(hostname: "db", port: 5432, username: "u", password: "p", database: "d")

    assert from_repo[:hostname] == "db"
    assert from_repo[:channel_name] == "acme_cluster"

    from_url = Cluster.postgres(url: "ecto://u:p@10.0.0.5:6432/orders")

    assert {from_url[:hostname], from_url[:port], from_url[:database]} ==
             {"10.0.0.5", 6432, "orders"}
  end
end
