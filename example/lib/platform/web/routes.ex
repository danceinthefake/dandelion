defmodule Platform.Web.Routes do
  @moduledoc """
  The routes every project has, whatever its domains: the shell page, health
  and metrics. `App.Router` calls `routes/0` inside its own module.
  """
  import Phoenix.Router

  defmacro routes do
    quote do
      get "/", Platform.Web.PageHandler, :index
      get "/health", Platform.Web.HealthHandler, :show
      get "/metrics", Platform.Web.MetricsHandler, :show
    end
  end
end
