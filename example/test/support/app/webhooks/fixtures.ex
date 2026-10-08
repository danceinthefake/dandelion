defmodule App.Webhooks.Fixtures do
  @moduledoc "Test helpers for webhook endpoints."
  alias App.Webhooks.Services.EndpointService

  def endpoint_fixture(attrs \\ %{}) do
    {:ok, endpoint} =
      EndpointService.create(
        Map.merge(
          %{
            "url" => "https://hooks.example.com/#{System.unique_integer([:positive])}",
            "events" => ["order.created"]
          },
          attrs
        )
      )

    endpoint
  end
end
