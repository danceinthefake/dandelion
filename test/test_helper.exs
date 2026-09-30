{:ok, _} = Dandelion.TestRepo.start_link()
{:ok, _} = Oban.start_link(repo: Dandelion.TestRepo, testing: :manual)
Ecto.Adapters.SQL.Sandbox.mode(Dandelion.TestRepo, :manual)
ExUnit.start()
