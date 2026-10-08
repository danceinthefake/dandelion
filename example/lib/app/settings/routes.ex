defmodule App.Settings.Routes do
  @moduledoc """
  The routes of the settings domain: admins read and change flags while the app
  runs. `App.Router` calls `routes/0` inside its own module.
  """
  import Phoenix.Router

  defmacro routes do
    quote do
      # an admin is needed
      scope "/api" do
        pipe_through [:api, :authenticated, :admin]

        get "/flags", App.Settings.Handlers.FlagHandler, :index
        put "/flags/:key", App.Settings.Handlers.FlagHandler, :update
        delete "/flags/:key", App.Settings.Handlers.FlagHandler, :delete
      end
    end
  end
end
