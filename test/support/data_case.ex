defmodule Dandelion.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      use Oban.Testing, repo: Dandelion.TestRepo
      import Ecto.Query
      alias Dandelion.TestRepo
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Dandelion.TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
