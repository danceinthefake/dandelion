defmodule Platform.Cluster.Postgres do
  @moduledoc """
  A libcluster strategy: nodes find each other through a Postgres channel.

  Every `:heartbeat` ms, a node sends its name with `pg_notify`; every node
  `LISTEN`s on the channel and connects to the names it hears.

  Both Postgres connections reconnect by themselves, so a database outage
  only pauses discovery — it never crashes the node. (`libcluster_postgres`
  0.2 crash-looped here and took the whole app down with it.)
  """
  use GenServer
  use Cluster.Strategy

  alias Cluster.Strategy.State

  # node names look like acme@10.0.0.5
  @node_name ~r/\A[\w.-]+@[\w.-]+\z/

  @impl true
  def start_link([%State{} = state]), do: GenServer.start_link(__MODULE__, state)

  @impl true
  def init(%State{config: config} = state) do
    conn =
      Keyword.take(config, [
        :hostname,
        :port,
        :username,
        :password,
        :database,
        :ssl,
        :socket_options
      ])

    # Neither connection waits for the database: both start now and keep
    # retrying in the background.
    {:ok, listener} =
      Postgrex.Notifications.start_link(conn ++ [sync_connect: false, auto_reconnect: true])

    {_ok_or_eventually, _ref} = Postgrex.Notifications.listen(listener, config[:channel_name])
    {:ok, notifier} = Postgrex.start_link(conn ++ [pool_size: 1])

    send(self(), :heartbeat)
    {:ok, Map.put(state, :meta, %{notifier: notifier})}
  end

  @impl true
  def handle_info(:heartbeat, %State{config: config, meta: meta} = state) do
    # Fails while the database is away; the next heartbeat tries again.
    Postgrex.query(meta.notifier, "SELECT pg_notify($1, $2)", [
      config[:channel_name],
      Atom.to_string(node())
    ])

    Process.send_after(self(), :heartbeat, config[:heartbeat_interval])
    {:noreply, state}
  end

  def handle_info({:notification, _listener, _ref, _channel, name}, state) do
    node = if name =~ @node_name, do: String.to_atom(name)

    if node && node != node() && node not in Node.list() do
      Cluster.Strategy.connect_nodes(state.topology, state.connect, state.list_nodes, [node])
    end

    {:noreply, state}
  end
end
