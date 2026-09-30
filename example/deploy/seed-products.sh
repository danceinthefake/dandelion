#!/bin/sh
# Puts a few products into the running 3-node cluster (compose.cluster.yaml).
# Orders are priced from the products table, so a fresh database has nothing
# to order until it has products. `mix setup` seeds the same two for local
# development (priv/repo/seeds.exs); A and PROOF are for cluster-proof.sh.
set -eu
cd "$(dirname "$0")"

docker compose -f compose.cluster.yaml exec -T node1 bin/acme rpc '
  now = DateTime.utc_now()

  products =
    for {sku, name, price} <- [{"TEA-01", "Green tea", 1500}, {"CUP-02", "Tea cup", 4000}, {"A", "A", 100}, {"PROOF", "Proof", 100}] do
      %{sku: sku, name: name, price_cents: price, updated_at: now}
    end

  Platform.Database.Repo.insert_all("products", products, on_conflict: :nothing)
  IO.write("ok")
' >/dev/null
echo "products seeded"
