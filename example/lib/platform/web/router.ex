defmodule Platform.Web.Router do
  @moduledoc """
  Every route of every domain, in one place. ≈ the chi router in `main.go`.
  Full module names, so each route says which domain handles it.
  """
  use Platform.Web, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  get "/", Platform.Web.PageHandler, :index
  get "/health", Platform.Web.HealthHandler, :show
  get "/metrics", Platform.Web.MetricsHandler, :show

  # domain: accounts — anyone can register and log in
  pipeline :authenticated do
    plug App.Accounts.Handlers.Auth, :authenticate
  end

  pipeline :admin do
    plug App.Accounts.Handlers.Auth, :require_admin
  end

  scope "/api" do
    pipe_through :api

    post "/users", App.Accounts.Handlers.UserHandler, :create
    post "/session", App.Accounts.Handlers.SessionHandler, :create
  end

  # domain: shop — public: the catalogue, and the payment provider's webhook
  # (it has its own token)
  scope "/api" do
    pipe_through :api

    get "/products/:sku", App.Shop.Handlers.ProductHandler, :show
    post "/payments/webhook", App.Shop.Handlers.PaymentHandler, :webhook
  end

  # a login is needed
  scope "/api" do
    pipe_through [:api, :authenticated]

    get "/me", App.Accounts.Handlers.SessionHandler, :show

    post "/orders", App.Shop.Handlers.OrderHandler, :create
    get "/orders", App.Shop.Handlers.OrderHandler, :index
    get "/orders/:id", App.Shop.Handlers.OrderHandler, :show
    post "/orders/:id/cancel", App.Shop.Handlers.OrderHandler, :cancel
  end

  # an admin is needed
  scope "/api" do
    pipe_through [:api, :authenticated, :admin]

    put "/products/:sku", App.Shop.Handlers.ProductHandler, :update
  end
end
