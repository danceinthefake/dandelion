defmodule App.Shop.Workers.ExpireUnpaidOrders do
  @moduledoc """
  Cancels orders that stayed unpaid too long, every `:every_seconds`.

  ≈ in Go:

      go func() {
          t := time.NewTicker(every)
          for { select { case <-t.C: expireUnpaid(); case <-ctx.Done(): return } }
      }()

  In Elixir it's a process (a `GenServer`) started by the supervisor in
  `Platform.Application`. The differences that matter:

    * It has its own memory and can't corrupt anyone else's — no mutex.
    * If a pass crashes (say the database is down), the process dies and
      the supervisor starts a fresh one. No `recover`, no half-broken
      goroutine: "let it crash".
    * `run_now/1` asks it to do a pass immediately and returns the count —
      handy in tests and from a remote shell (`bin/acme remote`).

  Config (`config/runtime.exs`): `:max_age_seconds` (default 3600),
  `:every_seconds` (default 60), `:enabled` (off in tests).
  """
  use GenServer
  require Logger

  alias App.Shop.Services.OrderService

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Runs one pass now; returns how many orders were cancelled."
  @spec run_now(GenServer.server()) :: non_neg_integer()
  def run_now(server \\ __MODULE__), do: GenServer.call(server, :run_now)

  @impl true
  def init(opts) do
    state = %{
      max_age: Keyword.get(opts, :max_age_seconds, 3600),
      every: Keyword.get(opts, :every_seconds, 60)
    }

    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    expire(state)
    schedule(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:run_now, _from, state), do: {:reply, expire(state), state}

  defp expire(state) do
    count = OrderService.expire_unpaid(state.max_age)

    if count > 0,
      do: Logger.info("cancelled #{count} unpaid order(s) older than #{state.max_age}s")

    count
  end

  defp schedule(state), do: Process.send_after(self(), :tick, state.every * 1000)
end
