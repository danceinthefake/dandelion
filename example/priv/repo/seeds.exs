# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Platform.Database.Repo.insert!(%App.Shop.Models.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias App.Shop.Models.Product

for {sku, name, price} <- [{"TEA-01", "Green tea", 1500}, {"CUP-02", "Tea cup", 4000}] do
  Platform.Database.Repo.insert!(%Product{sku: sku, name: name, price_cents: price},
    on_conflict: :nothing
  )
end
