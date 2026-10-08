defmodule Dandelion.RateLimit do
  @moduledoc """
  A rate limit in memory, on each node. ≈ a Redis `INCR` with an expiry —
  but it lives inside the app, so a check costs no network trip.

  Start it in your supervision tree:

      Dandelion.RateLimit

  then, for one client (an IP address, a user id, an API key):

      case Dandelion.RateLimit.hit({:login, ip}, 10, :timer.minutes(1)) do
        {:allow, _count} -> proceed()
        {:deny, retry_after_ms} -> reply_429(retry_after_ms)
      end

  It counts in fixed windows: `limit` hits per `window` milliseconds, from the
  first hit in a window. A client can spend up to twice the limit across a
  window boundary; that is the price of one counter per client.

  **The limit is per node.** In a cluster of three behind a load balancer a
  client gets about three times the limit. That is on purpose: a limit that
  asked Postgres or the other nodes on every request would make the limiter
  the thing that fails when the cluster is struggling. It is there to stop a
  loop in a client or a password guesser, not to bill by the request. If you
  need an exact cluster-wide count, count in a table in Postgres.

  A node that restarts forgets its counts.
  """
  use GenServer

  @table __MODULE__
  @sweep :timer.minutes(1)

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Counts one hit for `key`. Returns `{:allow, count}` while `count` is within
  `limit`, then `{:deny, retry_after_ms}` until the window ends.
  """
  @spec hit(term(), pos_integer(), pos_integer()) ::
          {:allow, pos_integer()} | {:deny, pos_integer()}
  def hit(key, limit, window) when limit > 0 and window > 0 do
    now = System.system_time(:millisecond)
    start = div(now, window)
    expires = (start + 1) * window
    row = {{key, start}, 0, expires}

    case :ets.update_counter(@table, {key, start}, {2, 1}, row) do
      count when count <= limit -> {:allow, count}
      _over -> {:deny, max(expires - now, 1)}
    end
  end

  @doc "Forgets every count (for tests)."
  def reset, do: :ets.delete_all_objects(@table)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep)
end
