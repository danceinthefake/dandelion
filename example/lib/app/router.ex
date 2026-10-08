defmodule App.Router do
  @moduledoc """
  The app's front door: which domains answer on this server. Each domain lists
  its own routes in `lib/app/<domain>/routes.ex`; this file only calls them and
  holds the pipelines they share. ≈ the chi router in `main.go`, mounting one
  sub-router per package.
  """
  use Platform.Web, :router

  require App.Accounts.Routes
  require App.Shop.Routes
  require App.Audit.Routes
  require App.Files.Routes
  require App.Notifications.Routes
  require App.Settings.Routes
  require App.Webhooks.Routes
  import Platform.Web.Routes

  pipeline :api do
    plug :accepts, ["json"]
  end

  # a login is needed
  pipeline :authenticated do
    plug App.Accounts.Handlers.Auth, :authenticate
  end

  # an admin is needed
  pipeline :admin do
    plug App.Accounts.Handlers.Auth, :require_admin
  end

  routes()

  # domain: accounts
  App.Accounts.Routes.routes()

  # domain: shop
  App.Shop.Routes.routes()

  # domain: audit
  App.Audit.Routes.routes()

  # domain: files
  App.Files.Routes.routes()

  # domain: notifications
  App.Notifications.Routes.routes()

  # domain: settings
  App.Settings.Routes.routes()

  # domain: webhooks
  App.Webhooks.Routes.routes()
end
