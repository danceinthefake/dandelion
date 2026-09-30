defmodule App.Shop.Channels.OrderFeedChannel do
  @moduledoc """
  The live order feed (`orders:live`). ≈ a WebSocket handler in Go.

    * Joining replies with the latest orders and the name of this node.
    * Every order made on **any node** is pushed as `"order"` the moment it's
      saved (`Platform.Broadcast`, sent by `OrderService.create/1`). It is
      live only: a browser that was disconnected reloads the list on
      rejoin (the join reply).
    * Who's online: `"presence_state"` once, then `"presence_diff"`
      (`Platform.Realtime.Presence`).
  """
  use Phoenix.Channel

  alias App.Shop.Handlers.OrderJSON
  alias App.Shop.Services.OrderService
  alias Platform.Realtime.Presence

  @impl true
  def join("orders:live", _params, socket) do
    {:ok, %{orders: orders}} = OrderService.list(%{"per_page" => "20"})
    Phoenix.PubSub.subscribe(Platform.Broadcast, "orders")
    send(self(), :after_join)
    # `node`: which node this browser is connected to (the page shows it, so a
    # demo can show two browsers on two nodes)
    {:ok, %{orders: Enum.map(orders, &OrderJSON.order/1), node: Atom.to_string(node())}, socket}
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "unknown feed"}}

  @impl true
  def handle_info(:after_join, socket) do
    push(socket, "presence_state", Presence.list(socket))
    {:ok, _} = Presence.track(socket, socket.assigns.viewer_id, %{})
    {:noreply, socket}
  end

  def handle_info({:order_created, order}, socket) do
    push(socket, "order", OrderJSON.order(order))
    {:noreply, socket}
  end
end
