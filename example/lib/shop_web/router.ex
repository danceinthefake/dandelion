defmodule ShopWeb.Router do
  use ShopWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ShopWeb.Handlers do
    pipe_through :api

    post "/orders", OrderHandler, :create
    get "/orders", OrderHandler, :index
    get "/orders/:id", OrderHandler, :show
    post "/orders/:id/cancel", OrderHandler, :cancel
  end
end
