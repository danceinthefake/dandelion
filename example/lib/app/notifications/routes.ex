defmodule App.Notifications.Routes do
  @moduledoc """
  The routes of the notifications domain: admins see what was sent. `App.Router` calls
  `routes/0` inside its own module.
  """
  import Phoenix.Router

  defmacro routes do
    quote do
      # an admin is needed
      scope "/api" do
        pipe_through [:api, :authenticated, :admin]

        get "/emails", App.Notifications.Handlers.EmailHandler, :index
      end
    end
  end
end
