defmodule App.Shop.Routes do
  @moduledoc """
  The routes of the shop domain. `App.Router` calls `routes/0` inside its own
  module, so the paths stay whole (`/api/orders`).
  """
  import Phoenix.Router

  defmacro routes do
    quote do
      # public: the catalogue, and the payment provider's webhook (it has its own token)
      scope "/api" do
        pipe_through :api

        get "/products/:sku", App.Shop.Handlers.ProductHandler, :show
        post "/payments/webhook", App.Shop.Handlers.PaymentHandler, :webhook
      end

      # a login is needed
      scope "/api" do
        pipe_through [:api, :authenticated]

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
  end
end
