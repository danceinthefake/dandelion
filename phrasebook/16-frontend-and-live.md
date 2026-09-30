# 16. Frontend and live updates

**In Go** — the frontend is usually a separate deployment (static hosting or
an nginx), and live updates mean a WebSocket hub you write with gorilla, a map
of connections behind a mutex, and Redis pub/sub so every instance's hub hears
the same events:

```go
type Hub struct {
    mu    sync.Mutex
    conns map[*websocket.Conn]bool
}
func (h *Hub) Broadcast(msg []byte) { /* lock, range, write, drop the dead ones */ }
// …and a goroutine that reads Redis and calls Broadcast
```

**In Elixir** — the Vue app is built into the release and the WebSocket is a
Phoenix **channel**: a process per connected browser.

- The app: [`assets/`](../example/assets) — Vue 3 and
  [blessing-ui](https://ui.blessing.id), built by Vite into `priv/static/app`
  and served by the same release ([`page_handler.ex`](../example/lib/platform/web/page_handler.ex)).
  Node is only needed to build it; `--no-frontend` leaves it out.
- The socket: [`user_socket.ex`](../example/lib/platform/web/user_socket.ex) at
  `/socket`; the topic is
  [`order_feed_channel.ex`](../example/lib/app/shop/channels/order_feed_channel.ex).

```elixir
def join("orders:live", _params, socket) do
  Phoenix.PubSub.subscribe(Platform.Broadcast, "orders")    # the same broadcast as page 13
  {:ok, %{orders: latest_orders()}, socket}                  # what the browser shows on open
end

def handle_info({:order_created, order}, socket) do
  push(socket, "order", OrderJSON.order(order))              # to this browser
  {:noreply, socket}
end
```

An order made on any node is broadcast to all nodes, each node's channel
processes push it to their browsers: that is the whole "hub". No map, no mutex,
no Redis. The browser side is a few lines
([`OrderFeed.vue`](../example/assets/src/OrderFeed.vue)):

```js
const channel = socket.channel("orders:live")
channel.on("order", (o) => (orders.value = [o, ...orders.value]))
channel.join().receive("ok", ({ orders: latest }) => (orders.value = latest))
```

| Go | Elixir |
|---|---|
| a hub goroutine + connection map + mutex | a channel: one process per browser |
| Redis pub/sub so every instance hears | `Platform.Broadcast` |
| online users in a Redis set with expiry | `Platform.Realtime.Presence` |
| reconnect and replay logic | the client library rejoins; the join reply reloads the list |
| frontend on static hosting, CORS | same origin: served by the release |

It is live only: a browser that was offline misses the pushes and gets the
current list when it rejoins. Who is online comes from `Presence` — each
connection is tracked while it lives, across nodes, and the count in the
sidebar is that list.

**Why:** every connection being its own cheap process is what makes a hub
unnecessary. There is nothing to lock because nothing is shared.
