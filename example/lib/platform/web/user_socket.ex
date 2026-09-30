defmodule Platform.Web.UserSocket do
  @moduledoc """
  The browser's WebSocket (Phoenix Channels), at `/socket`. ≈ a Pusher /
  socket.io server — one per node, and a message sent on one node reaches
  sockets on all of them (`Platform.Broadcast`).

  Every connection gets a random `viewer_id` (who's online needs a name; this
  example has no login — put your own identity here).
  """
  use Phoenix.Socket

  # domain: shop
  channel "orders:*", App.Shop.Channels.OrderFeedChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    viewer_id = 6 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {:ok, assign(socket, :viewer_id, viewer_id)}
  end

  @impl true
  def id(_socket), do: nil
end
