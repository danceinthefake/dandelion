defmodule Dandelion.Cluster do
  @moduledoc """
  Nodes finding each other. ≈ service discovery (Consul, Kubernetes DNS).

  Every node announces itself on a Postgres channel (`NOTIFY`) every 5
  seconds and connects to the nodes it hears from
  ([libcluster](https://libcluster.hexdocs.pm) with our strategy,
  `Dandelion.Cluster.Postgres`). Nothing extra to run: the database is
  already there. Once connected, nodes talk to each other directly — a
  `Phoenix.PubSub` broadcast reaches every node, and any node can call any
  other.

  Start it in your supervision tree:

      {Dandelion.Cluster, otp_app: :my_app, repo: MyApp.Repo}

  Only when this node runs distributed (a release; `iex --name` in dev);
  `mix phx.server` and tests stay single.

    * Needs a **direct** Postgres connection: `LISTEN` doesn't work through
      PgBouncer in transaction mode. `config :my_app, Dandelion.Cluster,
      database_url: "ecto://…"` points past a pooler; otherwise the repo's
      own settings are used.
    * If Postgres is down, connected nodes stay connected and nothing
      crashes; new nodes join once it's back.
    * A node that dies is noticed when its connection drops — at once if it
      crashed, within `net_ticktime` (60 s) if the network went silent.

  Options: `:otp_app` and `:repo` (both required). The channel name is
  `"<otp_app>_cluster"` — not the Erlang cookie (which libcluster_postgres
  used by default): the channel name is visible to anyone who can see the
  database's queries.
  """

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start:
        {Cluster.Supervisor, :start_link, [[topologies(opts), [name: __MODULE__.Supervisor]]]},
      type: :supervisor
    }
  end

  @doc "libcluster topologies: none unless this node runs distributed."
  def topologies(opts) do
    if Node.alive?(),
      do: [postgres: [strategy: Dandelion.Cluster.Postgres, config: postgres(opts)]],
      else: []
  end

  @doc false
  # Connection settings: `database_url` from the app's config, else the repo's own.
  def postgres(opts, repo_config \\ nil) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    repo_config = repo_config || Keyword.fetch!(opts, :repo).config()

    url = Application.get_env(otp_app, __MODULE__)[:database_url] || repo_config[:url]
    conn = if url, do: Ecto.Repo.Supervisor.parse_url(url), else: repo_config

    conn
    |> Keyword.take([:hostname, :port, :username, :password, :database, :ssl, :socket_options])
    |> Keyword.merge(channel_name: "#{otp_app}_cluster", heartbeat_interval: 5_000)
  end
end
