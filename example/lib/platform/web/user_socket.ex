defmodule Platform.Web.UserSocket do
  @moduledoc """
  The browser's WebSocket (Phoenix Channels), at `/socket`. ≈ a Pusher /
  socket.io server — one per node, and a message sent on one node reaches
  sockets on all of them (`Platform.Broadcast`).

  A connection needs the login token (`/socket?token=…`), the same one the API
  takes: no token, a bad or an expired one, and the connection is refused. Every
  connection also gets a random `viewer_id` for the "who's online" list.
  """
  use Phoenix.Socket

  alias App.Accounts.Handlers.Token

  # domain: shop
  channel "orders:*", App.Shop.Channels.OrderFeedChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Token.verify(token) do
      {:ok, user} ->
        viewer_id = 6 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
        {:ok, socket |> assign(:viewer_id, viewer_id) |> assign(:current_user, user)}

      {:error, _} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(_socket), do: nil
end
