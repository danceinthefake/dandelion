[English](../10-tests.md) · **Bahasa Indonesia**

# 10. Test

**Di Go** — table-driven:

```go
func TestCreateRejectsInvalid(t *testing.T) {
    cases := []struct{ name string; in NewOrder; want map[string][]string }{
        {"missing email", NewOrder{Email: ""}, map[string][]string{"customer_email": {"can't be blank"}}},
        // …
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) { … })
    }
}
```

**Di Elixir** — tabel yang sama, berupa list of tuple
([`test/shop/services/order_service_test.exs`](../../example/test/shop/services/order_service_test.exs#L19)):

```elixir
test "rejects invalid input" do
  cases = [
    {"missing email", %{"customer_email" => nil}, %{customer_email: ["can't be blank"]}},
    {"bad email", %{"customer_email" => "sari"}, %{customer_email: ["must be an email address"]}},
    {"no items", %{"items" => []}, %{items: ["can't be blank"]}}
    # …
  ]

  for {name, overrides, expected} <- cases do
    assert {:error, changeset} = OrderService.create(order_params(overrides)), name
    assert errors(changeset) == expected, name
  end
end
```

| Go | Elixir |
|---|---|
| `go test ./...` | `mix test` (`mix test path/to/file.exs:19` untuk satu test) |
| subtest `t.Run` | blok `describe` + `test` |
| `if got != want { t.Errorf(…) }` | `assert got == want` (menampilkan keduanya kalau gagal) |
| `t.Parallel()` | `use Shop.DataCase, async: true` |
| database test di dalam tx yang di-rollback | sama: *sandbox* Ecto me-rollback setiap test |
| helper `newTestOrder(t)` | [`test/support/fixtures.ex`](../../example/test/support/fixtures.ex) |
| `httptest.NewRecorder` | `ShopWeb.ConnCase`: `post(conn, "/api/orders", params)` ([test handler](../../example/test/shop_web/handlers/order_handler_test.exs)) |

**Kenapa:** test dengan `async: true` berjalan paralel, masing-masing di
dalam transaksi database sendiri — cepat, dan mereka tidak bisa melihat data
satu sama lain.
