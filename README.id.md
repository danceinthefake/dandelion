[English](README.md) · **Bahasa Indonesia**

# dandelion

**Kesederhanaan dengan ketangguhan dan keceriaan.**

Titik awal untuk developer Go yang menulis service Elixir pertamanya —
mulai dari satu service, lalu kembangkan menjadi cluster.

- [`example/`](example) — `shop`, JSON API kecil yang disusun seperti
  service Go (router → handler → service → repo → model), lengkap dengan
  test, background job, dan Docker image untuk release. Inilah yang
  dihasilkan oleh `mix dandelion.new`.
- [`phrasebook/id/`](phrasebook/id) — kamus Go → Elixir: untuk setiap
  kebiasaan di Go, cara Elixir-nya, dengan link ke file yang tepat di
  `example/`.
- [`installer/`](installer) — generator `mix dandelion.new` (package hex
  `dandelion_new`). Sebelum dipublikasikan:
  `cd installer && mix archive.build && mix archive.install dandelion_new-0.1.0.ez`,
  lalu `mix dandelion.new my_app` di mana saja.
- [`DESIGN.md`](DESIGN.md) — kenapa dibangun dengan cara ini (bahasa Inggris).

Nama: *dandelion* — **kesederhanaan dengan ketangguhan dan keceriaan.**
Bunga paling sederhana; tumbuh di sela retakan beton dan selalu tumbuh
kembali setiap kali dicabut; bijinya terbang terbawa angin — satu bunga
menjadi banyak, seperti service yang dimulai dari satu node lalu tumbuh
menjadi cluster.
