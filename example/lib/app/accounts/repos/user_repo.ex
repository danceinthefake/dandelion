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

  @doc "Sets a new password hash (the plain password never gets here)."
  def update_password(%User{} = user, hash) do
    user
    |> Ecto.Changeset.change(
      password_hash: hash,
      email_confirmed_at: user.email_confirmed_at || DateTime.utc_now()
    )
    |> Repo.update()
  end

  @doc "Marks the address confirmed (once)."
  def confirm_email(%User{email_confirmed_at: nil} = user),
    do: user |> Ecto.Changeset.change(email_confirmed_at: DateTime.utc_now()) |> Repo.update()

  def confirm_email(%User{} = user), do: {:ok, user}

  @doc "Inserts a user from a changeset."
  def insert(%Ecto.Changeset{} = changeset), do: Repo.insert(changeset)
end
