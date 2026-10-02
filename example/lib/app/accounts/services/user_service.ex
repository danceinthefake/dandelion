defmodule App.Accounts.Services.UserService do
  @moduledoc """
  Users and logging in. ≈ `service/users.go`. No HTTP here: tokens and headers
  are the handlers' business (`App.Accounts.Handlers.Token`).
  """
  alias App.Accounts.Models.User
  alias App.Accounts.Services.Password
  alias Platform.Database.Repos.UserRepo

  @doc """
  Registers a user. `params`: `"email"`, `"password"`. The role is the second
  argument — a request must never choose it — and defaults to `"customer"`.
  """
  @spec register(map(), String.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register(params, role \\ "customer") do
    changeset = User.register_changeset(params, role)

    if changeset.valid? do
      changeset
      |> Ecto.Changeset.put_change(:password_hash, Password.hash(changeset.changes.password))
      |> Ecto.Changeset.delete_change(:password)
      |> UserRepo.insert()
    else
      # (no hashing for input we are going to refuse)
      {:error, %{changeset | action: :insert}}
    end
  end

  @doc """
  Checks an email and password. The answer is the same for "no such email" and
  "wrong password": `{:error, :unauthorized}`.
  """
  @spec authenticate(term(), term()) :: {:ok, User.t()} | {:error, :unauthorized}
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    case UserRepo.get_by_email(email |> String.trim() |> String.downcase()) do
      nil ->
        Password.verify_nothing()
        {:error, :unauthorized}

      user ->
        if Password.verify(password, user.password_hash),
          do: {:ok, user},
          else: {:error, :unauthorized}
    end
  end

  def authenticate(_email, _password), do: {:error, :unauthorized}

  @doc "One user."
  @spec get(integer()) :: {:ok, User.t()} | {:error, :not_found}
  def get(id) do
    case UserRepo.get(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc "Is this user an admin?"
  def admin?(%User{role: role}), do: role == "admin"
end
