[English](../README.md) · **Bahasa Indonesia**

# Kamus Go → Elixir

Untuk developer Go yang menulis service Elixir pertamanya. Setiap halaman
menunjukkan cara kamu melakukan sesuatu di Go, caranya di Elixir, di mana hal
itu terjadi di [`../../example`](../../example) (service `shop` yang dibuat
oleh `mix dandelion.new`), dan satu kalimat tentang *kenapa* Elixir melakukannya
dengan cara itu.

Halaman-halamannya mengikuti perjalanan sebuah request, dari `mix` sampai
crash:

1. [Struktur project dan `mix`](01-layout-and-mix.md) — `go mod`, `go run`, `go test`
2. [Saat aplikasi start](02-starting-up.md) — `main.go` vs supervision tree
3. [Routing dan handler](03-routing-and-handlers.md) — chi vs router + handler
4. [Error sebagai nilai](04-errors-as-values.md) — `(value, err)` vs `{:ok, _}` / `{:error, _}` dan `with`
5. [Struct dan validasi](05-structs-and-validation.md) — struct vs schema dan changeset
6. [Service dan transaksi](06-services-and-transactions.md) — `sql.Tx` vs `Repo.transact`
7. [Repository dan query](07-repositories-and-queries.md) — `database/sql` / sqlc vs Ecto
8. [Konkurensi](08-concurrency.md) — goroutine dan `context` vs process dan `Task`
9. [State yang hidup lebih lama dari request](09-state.md) — mutex vs process yang memiliki state
10. [Test](10-tests.md) — `testing` vs ExUnit
11. [Konfigurasi dan release](11-config-and-releases.md) — konfigurasi env + Dockerfile vs `runtime.exs` + `mix release`
12. [Saat terjadi crash](12-when-it-crashes.md) — `panic` / `recover` vs supervisor

Urutan membaca: halaman 1–7 sudah cukup untuk mengubah contoh; halaman 8, 9
dan 12 adalah tempat Elixir paling berbeda dari Go — dan alasan kenapa
Elixir layak dipelajari.
