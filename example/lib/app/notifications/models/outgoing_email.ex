defmodule App.Notifications.Models.OutgoingEmail do
  @moduledoc """
  An email we mean to send, and what became of it: `queued` (not delivered yet), `sent`
  (the mail server accepted it) or `failed` (it said no for good: a bad address).
  """
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec]
  schema "outgoing_emails" do
    field :dedupe_key, :string
    field :kind, :string
    field :to_address, :string
    field :subject, :string
    field :body, :string
    field :status, :string, default: "queued"
    field :attempts, :integer, default: 0
    field :last_error, :string
    field :sent_at, :utc_datetime_usec
    timestamps()
  end

  @type t :: %__MODULE__{}
end
