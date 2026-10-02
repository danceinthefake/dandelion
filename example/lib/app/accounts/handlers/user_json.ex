defmodule App.Accounts.Handlers.UserJSON do
  @moduledoc """
  The JSON shape of users. The password hash is never part of it.
  """
  alias App.Accounts.Models.User

  def user(%User{} = u), do: %{id: u.id, email: u.email, role: u.role}
end
