[English](../12-when-it-crashes.md) · **Bahasa Indonesia**

# 12. Saat terjadi crash

**Di Go** — panic di sebuah goroutine menjatuhkan seluruh program kecuali
kamu `recover`, dan background goroutine yang mati ya… berhenti begitu saja:

```go
go func() {
    defer func() {
        if r := recover(); r != nil { log.Printf("job crashed: %v", r) }  // and now?
    }()
    for range ticker.C { expireUnpaid() }
}()
```

**Di Elixir** — crash hanya mengakhiri **satu process**, dan **supervisor**-nya
menjalankan process yang baru ([`lib/shop/application.ex`](../../example/lib/shop/application.ex#L9)):

```elixir
opts = [strategy: :one_for_one, name: Shop.Supervisor]
Supervisor.start_link(children, opts)
```

`:one_for_one`: kalau satu child mati, hanya child itu yang dijalankan ulang.
Contohnya menguji persis hal ini
([`test/shop/jobs/expire_unpaid_orders_test.exs`](../../example/test/shop/jobs/expire_unpaid_orders_test.exs)):
test mematikan job-nya, menunggu supervisor menjalankan yang baru, lalu
memastikan job yang baru tetap membatalkan order.

Artinya dalam keseharian:

- Bug di satu request HTTP membuat process request itu crash: client
  menerima 500, semua request lain tetap berjalan.
- Database hilang selama satu menit: job crash di tick berikutnya,
  dijalankan ulang, dan bekerja lagi setelah database kembali — tanpa kode
  tambahan untuk itu.
- Tidak ada blok `recover` di sekitar logika bisnis: tulis jalur normalnya
  (dengan `{:error, _}` untuk error yang memang kamu *harapkan*,
  [halaman 4](04-errors-as-values.md)), dan biarkan hal yang tidak terduga
  crash.

| Go | Elixir |
|---|---|
| `panic` | `raise` / match yang gagal — process-nya berhenti |
| `recover` | supervisor yang menjalankan ulang process (bukan di kode kamu) |
| background goroutine yang mati | dijalankan ulang secara otomatis |
| crash = seluruh program | crash = satu process |

**Kenapa:** inilah alasan untuk belajar Elixir. Kegagalan tetap kecil,
pemulihannya sudah menjadi bagian dari struktur alih-alih ditulis manual,
dan service tetap berjalan melewati jenis error yang biasanya membangunkan
seseorang jam 3 pagi.
