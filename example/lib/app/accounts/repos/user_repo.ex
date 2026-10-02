defmodule Platform.Database.Repos.UserRepo do
  @moduledoc "User queries — and nothing else. ≈ `repo/users.go`."
  alias App.Accounts.Models.User
  alias Platform.Database.Repo

  @doc "A user, or nil."
  @spec get(integer()) :: User.t() | nil
  def get(id), do: Repo.get(User, id)

  @doc "The user with this (lower-case) email, or nil."
  @spec get_by_email(String.t()) :: User.t() | nil
  def get_by_email(email), do: Repo.get_by(User, email: email)

  @doc "Inserts a user from a changeset."
  def insert(%Ecto.Changeset{} = changeset), do: Repo.insert(changeset)
end
