defmodule App.Accounts.Models.UserToken do
  @moduledoc "A one-time link sent by email: what it is for, when it ends, and whether it was used."
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]
  schema "user_tokens" do
    field :user_id, :integer
    field :kind, :string
    field :token_hash, :string
    field :expires_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec
    timestamps()
  end

  @type t :: %__MODULE__{}
end
