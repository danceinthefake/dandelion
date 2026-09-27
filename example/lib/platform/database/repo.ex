defmodule Platform.Database.Repo do
  use Ecto.Repo,
    otp_app: :acme,
    adapter: Ecto.Adapters.Postgres
end
