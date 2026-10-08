defmodule App.Files.Routes do
  @moduledoc """
  The routes of the files domain: a logged-in user uploads, lists, downloads and
  removes their files. `App.Router` calls `routes/0` inside its own module.
  """
  import Phoenix.Router

  defmacro routes do
    quote do
      # a login is needed
      scope "/api" do
        pipe_through [:api, :authenticated]

        post "/files", App.Files.Handlers.FileHandler, :create
        get "/files", App.Files.Handlers.FileHandler, :index
        get "/files/:id", App.Files.Handlers.FileHandler, :show
        delete "/files/:id", App.Files.Handlers.FileHandler, :delete
      end
    end
  end
end
