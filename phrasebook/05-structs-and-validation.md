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

**In Elixir** — an Ecto **schema** describes the struct and its table
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

and a **changeset** validates input — "the changes we want, and what's wrong
with them" ([`order.ex`](../example/lib/app/shop/models/order.ex#L33)):

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

It collects **every** error, including per item, and the fallback handler
turns them into:

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

**Why:** data and functions live apart — a struct is just data, and any
function can take it. Structs are immutable: `put_total/1` returns a *new*
changeset instead of changing the one it got.
