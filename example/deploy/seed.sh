#!/bin/sh
# Puts a few products and two users into the running 3-node cluster
# (compose.cluster.yaml). Orders are priced from the products table, and the
# API needs a login, so a fresh database has nothing to try until it has both.
# `mix setup` seeds the same two products and users for local development
# (priv/repo/seeds.exs); A and PROOF are for cluster-proof.sh.
#
# The users, admin@example.com and customer@example.com, have the password
# local-password-1 — public, for this local cluster only.
set -eu
cd "$(dirname "$0")"

docker compose -f compose.cluster.yaml exec -T node1 bin/acme rpc '
  now = DateTime.utc_now()

  products =
    for {sku, name, price} <- [{"TEA-01", "Green tea", 1500}, {"CUP-02", "Tea cup", 4000}, {"A", "A", 100}, {"PROOF", "Proof", 100}] do
      %{sku: sku, name: name, price_cents: price, updated_at: now}
    end

  Platform.Database.Repo.insert_all("products", products, on_conflict: :nothing)

  for {email, role} <- [{"admin@example.com", "admin"}, {"customer@example.com", "customer"}] do
    unless Platform.Database.Repos.UserRepo.get_by_email(email) do
      {:ok, _} = App.Accounts.Services.UserService.register(%{"email" => email, "password" => "local-password-1"}, role)
    end
  end

  IO.write("ok")
' >/dev/null
echo "products and users seeded"
