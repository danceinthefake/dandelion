**English** · [Bahasa Indonesia](id/10-tests.md)

# 10. Tests

**In Go** — table-driven:

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

**In Elixir** — the same table, a list of tuples
([`test/shop/services/order_service_test.exs`](../example/test/shop/services/order_service_test.exs#L19)):

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
| `go test ./...` | `mix test` (`mix test path/to/file.exs:19` for one test) |
| `t.Run` subtests | `describe` blocks + `test` |
| `if got != want { t.Errorf(…) }` | `assert got == want` (prints both on failure) |
| `t.Parallel()` | `use Shop.DataCase, async: true` |
| test DB in a tx rolled back after | the same: the Ecto *sandbox* rolls back each test |
| `newTestOrder(t)` helpers | [`test/support/fixtures.ex`](../example/test/support/fixtures.ex) |
| `httptest.NewRecorder` | `ShopWeb.ConnCase`: `post(conn, "/api/orders", params)` ([handler tests](../example/test/shop_web/handlers/order_handler_test.exs)) |

**Why:** `async: true` tests run in parallel, each inside its own database
transaction — fast, and they can't see each other's data.
