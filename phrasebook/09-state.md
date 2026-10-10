# 9. State that outlives a request

**In Go**, shared state sits behind a mutex:

```go
type Counter struct { mu sync.Mutex; n map[string]int }

func (c *Counter) Inc(k string) { c.mu.Lock(); defer c.mu.Unlock(); c.n[k]++ }
func (c *Counter) Get(k string) int { c.mu.Lock(); defer c.mu.Unlock(); return c.n[k] }
```

**In Elixir**, nothing is shared. One process owns the state, and other processes ask it with a message. A `GenServer` is that process with the plumbing done:

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

It handles one message at a time, so no race exists that a lock must stop.

The example has no `GenServer` of its own, on purpose. Its shared state lives in Postgres. What it runs on has many of them: the queues and the cron of Oban, the live broadcast (Phoenix.PubSub), the cache, and the database pool. Each one is a process that owns its state.

| Go | Elixir |
|---|---|
| `sync.Mutex` around a map | a process owning the map |
| method call | `GenServer.call` (waits for the answer) or `cast` (does not wait) |
| `time.Ticker` | inside one process, `Process.send_after(self(), :tick, ms)`; once per cluster, a cron entry ([`lib/platform/cron.ex`](../example/lib/platform/cron.ex)) |

**Why:** Most state belongs in the database. For the rest (a cache or a counter), one owner process is simpler than locks. It also cannot deadlock on itself.
