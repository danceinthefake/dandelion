defmodule Platform.Web do
  @moduledoc """
  The entrypoint for the web layer: what every router and handler starts
  with.

      use Platform.Web, :router
      use Platform.Web, :handler

  The definitions below run for every handler, so keep them short:
  imports, uses and aliases only.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  # Handlers are Phoenix controllers; the name follows Go vocabulary.
  # `use Platform.Web, :handler`
  def handler do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: Platform.Web.Endpoint,
        router: Platform.Web.Router,
        statics: Platform.Web.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
