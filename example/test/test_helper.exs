# The catalogue the order tests use (products aren't rolled back with the
# sandbox: the test database keeps them, and inserting twice is harmless).
now = DateTime.utc_now()

Platform.Database.Repo.insert_all(
  "products",
  for {sku, name, price} <- [
        {"TEA-01", "Green tea", 1500},
        {"CUP-02", "Tea cup", 4000},
        {"BIG-99", "Very expensive", 1_000_000_000_000}
      ] do
    %{sku: sku, name: name, price_cents: price, updated_at: now}
  end,
  on_conflict: :nothing
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Platform.Database.Repo, :manual)
