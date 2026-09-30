defmodule App.Shop.Services.ProductServiceTest do
  use Platform.DataCase, async: true

  import App.Shop.Fixtures

  alias App.Shop.Services.ProductService
  alias Platform.Database.Repo

  test "reads go through the cache" do
    p = product_fixture()
    assert {:ok, %{price_cents: 1500}} = ProductService.get(p.sku)

    # changed behind the service's back: the cached copy is still served
    Repo.query!("UPDATE products SET price_cents = 1 WHERE sku = $1", [p.sku])
    assert {:ok, %{price_cents: 1500}} = ProductService.get(p.sku)
  end

  test "changing a price through the service is seen by the next read" do
    p = product_fixture()
    assert {:ok, %{price_cents: 1500}} = ProductService.get(p.sku)

    assert {:ok, %{price_cents: 1600}} =
             ProductService.update_price(p.sku, %{"price_cents" => 1600})

    assert {:ok, %{price_cents: 1600}} = ProductService.get(p.sku)
  end

  test "a product that doesn't exist" do
    assert {:error, :not_found} = ProductService.get("NOPE")
    assert {:error, :not_found} = ProductService.update_price("NOPE", %{"price_cents" => 1})
  end

  test "a price must be a whole number from 0 up" do
    p = product_fixture()

    for bad <- [
          %{},
          %{"price_cents" => -1},
          %{"price_cents" => "x"},
          %{"price_cents" => 10_000_000_000_000_000_000}
        ] do
      assert {:error, %Ecto.Changeset{}} = ProductService.update_price(p.sku, bad)
    end
  end
end
