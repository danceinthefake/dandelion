[English](../09-state.md) · **Bahasa Indonesia**

# 9. State yang hidup lebih lama dari request

**Di Go** — state bersama yang dilindungi mutex:

```go
type Counter struct { mu sync.Mutex; n map[string]int }

func (c *Counter) Inc(k string) { c.mu.Lock(); defer c.mu.Unlock(); c.n[k]++ }
func (c *Counter) Get(k string) int { c.mu.Lock(); defer c.mu.Unlock(); return c.n[k] }
```

**Di Elixir** — tidak ada yang dibagi. Satu process **memiliki** state-nya;
yang lain memintanya lewat pesan. `GenServer` adalah process seperti itu
dengan semua plumbing-nya sudah disediakan:

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

Dia menangani satu pesan dalam satu waktu, jadi tidak ada race condition
yang perlu dikunci.

Background job di contoh juga sebuah `GenServer`
([`lib/shop/jobs/expire_unpaid_orders.ex`](../../example/lib/shop/jobs/expire_unpaid_orders.ex#L25)):
state-nya adalah pengaturannya, pesan timer (`:tick`) membangunkannya, dan
`run_now/1` adalah `call` yang bisa dilakukan kode lain:

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
| `sync.Mutex` di sekitar sebuah map | process yang memiliki map itu |
| pemanggilan method | `GenServer.call` (menunggu jawaban) / `cast` (tidak menunggu) |
| `time.Ticker` | `Process.send_after(self(), :tick, ms)` |

**Kenapa:** sebagian besar state tempatnya di database. Untuk sisanya
(cache, rate limit, jadwal sebuah job), satu process pemilik lebih sederhana
daripada lock — dan tidak bisa deadlock dengan dirinya sendiri.
