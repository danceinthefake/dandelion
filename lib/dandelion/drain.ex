defmodule Dandelion.Drain do
  @moduledoc """
  Taking a node out of rotation before it stops. ≈ Kubernetes `preStop` +
  readiness probe.

  When a node is told to stop (SIGTERM, a deploy, `docker stop`), a load
  balancer needs a moment to notice and stop sending it requests. Without that
  moment, the requests that arrive in between are refused. So: first the node
  *says* it is leaving — its `/health` answers 503 — and keeps serving for a
  short while; only then does it stop accepting connections and finish the
  requests in flight.

  Call `start/1` from your application's `prep_stop/1`, which runs before the
  supervision tree is shut down:

      def prep_stop(state) do
        Dandelion.Drain.start(5_000)
        state
      end

  and have the health check ask `draining?/0`:

      if Dandelion.Drain.draining?(), do: 503, else: 200

  Order of shutdown after that is the supervision tree's, in reverse: put the
  web server last in the child list so it stops first, and the jobs and the
  database after it.
  """

  @key {__MODULE__, :draining}

  @doc "Marks this node as leaving, then waits `delay` milliseconds."
  @spec start(non_neg_integer()) :: :ok
  def start(delay) when is_integer(delay) and delay >= 0 do
    :persistent_term.put(@key, true)
    Process.sleep(delay)
  end

  @doc "True once `start/1` has been called on this node."
  @spec draining?() :: boolean()
  def draining?, do: :persistent_term.get(@key, false)

  @doc "Puts the node back in rotation (for tests)."
  def reset, do: :persistent_term.erase(@key) && :ok
end
