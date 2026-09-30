defmodule Platform.Realtime.Presence do
  @moduledoc """
  Who is connected right now, across all nodes. ≈ Pusher presence channels,
  or a Redis set of online users with expiry — but without the expiry
  bookkeeping: an entry disappears when its connection does, and when a whole
  node dies the others drop its entries.

  Kept in memory and merged between nodes (a CRDT), so after a network split
  each side sees its own users and they merge when it heals. It is for
  showing who's online, not for deciding anything (DESIGN §10.3, rule 1).
  """
  use Phoenix.Presence, otp_app: :acme, pubsub_server: Platform.Broadcast
end
