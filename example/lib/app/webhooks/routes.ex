defmodule App.Webhooks.Routes do
  @moduledoc """
  The routes of the webhooks domain: admins register the URLs we send events to.
  `App.Router` calls `routes/0` inside its own module.
  """
  import Phoenix.Router

  defmacro routes do
    quote do
      # an admin is needed
      scope "/api" do
        pipe_through [:api, :authenticated, :admin]

        post "/webhooks", App.Webhooks.Handlers.EndpointHandler, :create
        get "/webhooks", App.Webhooks.Handlers.EndpointHandler, :index
        delete "/webhooks/:id", App.Webhooks.Handlers.EndpointHandler, :delete
      end
    end
  end
end
