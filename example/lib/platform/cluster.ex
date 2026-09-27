defmodule Platform.Cluster do
  @moduledoc """
  Nodes finding each other. ≈ service discovery (Consul, Kubernetes DNS).

  Every node announces itself on a Postgres channel (`NOTIFY`) every 5
  seconds and connects to the nodes it hears from
  ([libcluster](https://libcluster.hexdocs.pm) with our strategy,
  `Platform.Cluster.Postgres`).
  Nothing extra to run: the database is already there. Once connected,
  nodes talk to each other directly — `Platform.Broadcast` reaches every
  node, and any node can call any other.

  Only when this node runs distributed (a release; `iex --name` in dev);
  `mix phx.server` and tests stay single.

    * Needs a **direct** Postgres connection: `LISTEN` doesn't work through
      PgBouncer in transaction mode. `CLUSTER_DATABASE_URL` points past a
      pooler; otherwise `DATABASE_URL` is used.
    * If Postgres is down, connected nodes stay connected and nothing
      crashes; new nodes join once it's back.
    * A node that dies is noticed when its connection drops — at once if it
      crashed, within `net_ticktime` (60 s) if the network went silent.
  """

  alias Platform.Database.Repo

  # Not the Erlang cookie (libcluster_postgres's default): the channel name
  # is visible to anyone who can see the database's queries.
  @channel "acme_cluster"

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Cluster.Supervisor, :start_link, [[topologies(), [name: __MODULE__.Supervisor]]]},
      type: :supervisor
    }
  end

  @doc "libcluster topologies: none unless this node runs distributed."
  def topologies do
    if Node.alive?(),
      do: [postgres: [strategy: Platform.Cluster.Postgres, config: postgres()]],
      else: []
  end

  @doc false
  # Connection settings: CLUSTER_DATABASE_URL, else the repo's own.
  def postgres(repo_config \\ Repo.config()) do
    url = Application.get_env(:acme, __MODULE__)[:database_url] || repo_config[:url]
    conn = if url, do: Ecto.Repo.Supervisor.parse_url(url), else: repo_config

    conn
    |> Keyword.take([:hostname, :port, :username, :password, :database, :ssl, :socket_options])
    |> Keyword.merge(channel_name: @channel, heartbeat_interval: 5_000)
  end
end
