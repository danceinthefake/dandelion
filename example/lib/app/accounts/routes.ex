defmodule App.Accounts.Routes do
  @moduledoc """
  The routes of the accounts domain: register and log in. `App.Router` calls
  `routes/0` inside its own module, so the paths stay whole (`/api/users`).
  """
  import Phoenix.Router

  defmacro routes do
    quote do
      scope "/api" do
        pipe_through :api

        post "/users", App.Accounts.Handlers.UserHandler, :create
        post "/session", App.Accounts.Handlers.SessionHandler, :create
      end

      # a login is needed
      scope "/api" do
        pipe_through [:api, :authenticated]

        get "/me", App.Accounts.Handlers.SessionHandler, :show
      end
    end
  end
end
