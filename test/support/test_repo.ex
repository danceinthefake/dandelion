defmodule Dandelion.TestRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :dandelion, adapter: Ecto.Adapters.Postgres
end
