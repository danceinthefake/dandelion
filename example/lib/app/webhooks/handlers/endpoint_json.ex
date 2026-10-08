defmodule App.Webhooks.Handlers.EndpointJSON do
  @moduledoc "The JSON shape of a webhook endpoint."

  def endpoint(e, opts \\ []) do
    base = %{id: e.id, url: e.url, events: e.events, active: e.active}
    if opts[:secret], do: Map.put(base, :secret, e.secret), else: base
  end
end
