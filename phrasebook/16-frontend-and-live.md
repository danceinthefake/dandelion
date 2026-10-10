# 16. Frontend and live updates

**In Go**, the frontend is usually a separate deployment (static hosting or an nginx). Live updates need a WebSocket hub that you write with gorilla. The hub has a map of connections behind a mutex. Redis pub/sub lets the hub of every instance hear the same events:

```go
type Hub struct {
    mu    sync.Mutex
    conns map[*websocket.Conn]bool
}
func (h *Hub) Broadcast(msg []byte) { /* lock, range, write, drop the dead ones */ }
// …and a goroutine that reads Redis and calls Broadcast
```

**In Elixir**, the build puts the Vue app into the release, and the WebSocket is a Phoenix channel. A channel is a process for each connected browser.

- The app is in [`assets/`](../example/assets). It uses Vue 3 and [blessing-ui](https://ui.blessing.id). Vite builds it into `priv/static/app`, and the same release serves it ([`page_handler.ex`](../example/lib/platform/web/page_handler.ex)). You need Node only to build it. `--no-frontend` leaves it out.
- The socket is [`user_socket.ex`](../example/lib/platform/web/user_socket.ex) at `/socket`. The topic is in [`order_feed_channel.ex`](../example/lib/app/shop/channels/order_feed_channel.ex).

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

An order made on any node is broadcast to all nodes. The channel processes of each node push it to their browsers. This is the whole "hub". It has no map, no mutex, and no Redis. The browser side is a few lines ([`OrderFeed.vue`](../example/assets/src/OrderFeed.vue)):

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

The feed is live only. A browser that was offline misses the pushes. It gets the current list when it joins again. Who is online comes from `Presence`. The service tracks each connection while it lives, across nodes. The count in the sidebar is that list.

**Why:** Each connection is its own cheap process. This makes a hub unnecessary. You have nothing to lock, because nothing is shared.
