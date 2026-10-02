defmodule App.Accounts.Fixtures do
  @moduledoc "Test helpers for users and logging in."
  import Plug.Conn

  alias App.Accounts.Handlers.Token
  alias App.Accounts.Services.UserService

  @password "correct horse battery"

  def password, do: @password

  @doc "A user in the database (a customer unless `role` says otherwise)."
  def user_fixture(attrs \\ %{}, role \\ "customer") do
    email = "user-#{System.unique_integer([:positive])}@example.com"
    params = Map.merge(%{"email" => email, "password" => @password}, attrs)
    {:ok, user} = UserService.register(params, role)
    user
  end

  def admin_fixture(attrs \\ %{}), do: user_fixture(attrs, "admin")

  @doc "The conn, sending this user's token."
  def log_in(conn, user), do: put_req_header(conn, "authorization", "Bearer " <> Token.sign(user))
end
