# 5. Structs and validation

**In Go**:

```go
type Order struct {
    ID            int64
    CustomerEmail string
    Status        string
    TotalCents    int64
    Items         []OrderItem
}

func (o NewOrder) Validate() error {
    if o.CustomerEmail == "" { return fieldErr("customer_email", "can't be blank") }
    if len(o.Items) == 0 { return fieldErr("items", "can't be blank") }
    // …
}
```

**In Elixir**, an Ecto schema describes the struct and its table
([`lib/app/shop/models/order.ex`](../example/lib/app/shop/models/order.ex#L17)):

```elixir
schema "orders" do
  field :customer_email, :string
  field :status, :string, default: "pending"
  field :total_cents, :integer
  has_many :items, OrderItem
  timestamps()
end
```

A changeset validates input. It holds the changes that we want and what is wrong with them ([`order.ex`](../example/lib/app/shop/models/order.ex#L33)):

```elixir
def create_changeset(order \\ %__MODULE__{}, attrs) do
  order
  |> cast(attrs, [:customer_email])
  |> validate_required([:customer_email])
  |> validate_format(:customer_email, ~r/\A[^@\s]+@[^@\s]+\z/,
    message: "must be an email address"
  )
  |> validate_length(:customer_email, max: 254)
  |> cast_assoc(:items, with: &OrderItem.changeset/2, required: true)
  |> put_total()
end
```

The changeset collects every error, also the errors for each item. The fallback handler turns them into this:

```json
{"errors": {"customer_email": ["must be an email address"],
            "items": [{}, {"quantity": ["must be greater than 0"]}]}}
```

| Go | Elixir |
|---|---|
| `type Order struct` | `schema "orders"` → `%Order{}` |
| methods on the struct | functions in the module (`Order.create_changeset/2`) |
| `Validate() error` (first error) | changeset (all errors, per field) |
| `a \|> b \|> c` | `\|>` passes the result as the first argument: `c(b(a))` |

**Why:** Data and functions live apart. A struct is only data, and any function can take it. Structs are immutable. `put_total/1` returns a new changeset and does not change the changeset that it got.
