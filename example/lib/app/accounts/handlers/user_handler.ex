defmodule App.Accounts.Handlers.UserHandler do
  @moduledoc """
  Registration. ≈ `http/users.go`. Anyone can register, as a customer: the role
  isn't read from the request.
  """
  use Platform.Web, :handler

  alias App.Accounts.Handlers.UserJSON
  alias App.Accounts.Services.{AccountService, UserService}

  action_fallback Platform.Web.FallbackHandler

  # POST /api/users   {"email": "sari@example.com", "password": "at least 10 characters"}
  def create(conn, params) do
    with {:ok, user} <- UserService.register(Map.take(params, ["email", "password"])) do
      # (a job: a mail server that is down does not stop anybody registering)
      :ok = AccountService.send_confirmation(user)
      conn |> put_status(:created) |> json(UserJSON.user(user))
    end
  end
end
