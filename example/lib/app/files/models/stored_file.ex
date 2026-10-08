defmodule App.Files.Models.StoredFile do
  @moduledoc "A file someone uploaded: whose it is, what it is, where its bytes are."
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]
  schema "stored_files" do
    field :user_id, :integer
    field :filename, :string
    field :content_type, :string
    field :size, :integer
    field :sha256, :string
    field :storage_key, :string
    timestamps(updated_at: false)
  end

  @type t :: %__MODULE__{}

  @doc "A new row for bytes already stored; the constraints turn into errors, not raises."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> change(attrs)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:storage_key)
  end
end
