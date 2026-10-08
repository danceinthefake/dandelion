defmodule App.Audit.Routes do
  @moduledoc """
  The routes of the audit domain: admins read the log. `App.Router` calls `routes/0`
  inside its own module.
  """
  import Phoenix.Router

  defmacro routes do
    quote do
      # an admin is needed
      scope "/api" do
        pipe_through [:api, :authenticated, :admin]

        get "/audit", App.Audit.Handlers.AuditHandler, :index
      end
    end
  end
end
