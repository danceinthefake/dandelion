[English](../05-structs-and-validation.md) · **Bahasa Indonesia**

# 5. Struct dan validasi

**Di Go**:

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

**Di Elixir** — **schema** Ecto mendeskripsikan struct beserta tabelnya
([`lib/shop/models/order.ex`](../../example/lib/shop/models/order.ex#L17)):

```elixir
schema "orders" do
  field :customer_email, :string
  field :status, :string, default: "pending"
  field :total_cents, :integer
  has_many :items, OrderItem
  timestamps()
end
```

dan sebuah **changeset** memvalidasi input — "perubahan yang kita inginkan,
dan apa yang salah dengannya" ([`order.ex`](../../example/lib/shop/models/order.ex#L33)):

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

Changeset mengumpulkan **semua** error, termasuk per item, lalu fallback
handler mengubahnya menjadi:

```json
{"errors": {"customer_email": ["must be an email address"],
            "items": [{}, {"quantity": ["must be greater than 0"]}]}}
```

| Go | Elixir |
|---|---|
| `type Order struct` | `schema "orders"` → `%Order{}` |
| method pada struct | function di dalam module (`Order.create_changeset/2`) |
| `Validate() error` (error pertama) | changeset (semua error, per field) |
| `a \|> b \|> c` | `\|>` meneruskan hasil sebagai argumen pertama: `c(b(a))` |

**Kenapa:** data dan function dipisah — struct hanyalah data, dan function
apa pun bisa menerimanya. Struct bersifat immutable: `put_total/1`
mengembalikan changeset *baru*, bukan mengubah changeset yang diterimanya.
