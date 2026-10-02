defmodule App.Accounts.Models.User do
  @moduledoc """
  A user who can log in. ≈ `type User struct` in `model/user.go`, plus the
  validation of a registration.

  The password is never stored: only `password_hash` (see
  `App.Accounts.Services.Password`). `role` is `"customer"` or `"admin"`, and is
  never taken from a request.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(customer admin)

  @timestamps_opts [type: :utc_datetime_usec]
  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :role, :string, default: "customer"
    timestamps()
  end

  @type t :: %__MODULE__{}

  def roles, do: @roles

  @doc """
  Validates a registration (`email`, `password`). The email is kept lower-case.
  The password is limited at both ends: too short is guessable, too long is a
  way to make the server hash megabytes.
  """
  def register_changeset(attrs, role \\ "customer") when role in @roles do
    %__MODULE__{role: role}
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_format(:email, ~r/\A[^@\s]+@[^@\s]+\z/, message: "must be an email address")
    |> validate_length(:email, max: 254)
    |> validate_length(:password, min: 10, max: 200)
    |> unique_constraint(:email)
  end
end
