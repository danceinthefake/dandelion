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

  # domain: shop
  scope "/api" do
    pipe_through :api

    post "/orders", App.Shop.Handlers.OrderHandler, :create
    get "/orders", App.Shop.Handlers.OrderHandler, :index
    get "/orders/:id", App.Shop.Handlers.OrderHandler, :show
    post "/orders/:id/cancel", App.Shop.Handlers.OrderHandler, :cancel
    get "/products/:sku", App.Shop.Handlers.ProductHandler, :show
    put "/products/:sku", App.Shop.Handlers.ProductHandler, :update
    post "/payments/webhook", App.Shop.Handlers.PaymentHandler, :webhook
  end
end
