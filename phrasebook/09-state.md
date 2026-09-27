# 9. State that outlives a request

**In Go** — shared state behind a mutex:

```go
type Counter struct { mu sync.Mutex; n map[string]int }

func (c *Counter) Inc(k string) { c.mu.Lock(); defer c.mu.Unlock(); c.n[k]++ }
func (c *Counter) Get(k string) int { c.mu.Lock(); defer c.mu.Unlock(); return c.n[k] }
```

**In Elixir** — nothing is shared. One process **owns** the state; others
ask it by message. A `GenServer` is that process with the plumbing done:

```elixir
defmodule Counter do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def inc(key), do: GenServer.cast(__MODULE__, {:inc, key})
  def get(key), do: GenServer.call(__MODULE__, {:get, key})

  @impl true
  def init(state), do: {:ok, state}
  @impl true
  def handle_cast({:inc, key}, state), do: {:noreply, Map.update(state, key, 1, &(&1 + 1))}
  @impl true
  def handle_call({:get, key}, _from, state), do: {:reply, Map.get(state, key, 0), state}
end
```

It handles one message at a time, so there is no race to lock against.

The example's background job is a `GenServer` too
([`lib/app/shop/workers/expire_unpaid_orders.ex`](../example/lib/app/shop/workers/expire_unpaid_orders.ex#L25)):
its state is its settings, a timer message (`:tick`) wakes it up, and
`run_now/1` is a `call` other code can make:

```elixir
def handle_info(:tick, state) do
  expire(state)
  schedule(state)
  {:noreply, state}
end

def handle_call(:run_now, _from, state), do: {:reply, expire(state), state}

defp schedule(state), do: Process.send_after(self(), :tick, state.every * 1000)
```

| Go | Elixir |
|---|---|
| `sync.Mutex` around a map | a process owning the map |
| method call | `GenServer.call` (waits for the answer) / `cast` (doesn't) |
| `time.Ticker` | `Process.send_after(self(), :tick, ms)` |

**Why:** most state belongs in the database. For the rest (caches, rate
limits, a job's schedule), one owner process is simpler than locks — and it
can't deadlock on itself.
