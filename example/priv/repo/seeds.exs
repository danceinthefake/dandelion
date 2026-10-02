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

# Two users for trying the API and the web UI locally: an admin and a customer.
# The password is public (it's in this file): never seed users like this in
# production.
for {email, role} <- [{"admin@example.com", "admin"}, {"customer@example.com", "customer"}] do
  unless Platform.Database.Repos.UserRepo.get_by_email(email) do
    {:ok, _} =
      App.Accounts.Services.UserService.register(
        %{"email" => email, "password" => "local-password-1"},
        role
      )
  end
end
