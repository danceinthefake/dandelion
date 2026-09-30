# Running on N VMs

> A guide, **not tested on real VMs** (the proof in `cluster-proof.sh` runs
> three containers on one machine). Every step below is what those three
> containers do, spelled out for machines.

The shape: N VMs on a **private network**, each running the same image, all
talking to one Postgres, with a load balancer in front as the only way in.

```
internet → load balancer ─┬─► vm1 :4000 ┐
                          ├─► vm2 :4000 ├─ 9100 between the VMs ─ Postgres (private)
                          └─► vm3 :4000 ┘
```

## 1. Network

- VMs on a private network, **no public IPs**.
- Firewall, on each VM:
  - **9100** (Erlang distribution) open **only to the other app VMs**. Whoever
    reaches it with the cookie can run any code on the node.
  - **4000** (HTTP) open **only to the load balancer**.
  - Postgres open to the VMs only.
- Health check for the load balancer: `GET /health` (200 when the node and its
  database connection are fine, 503 otherwise).
- Keep the load balancer's idle timeout above a minute, and let it pass
  WebSocket upgrades on `/socket` (the live feed) — `nginx.conf` here shows the
  headers.

## 2. What each VM needs

The variables are in [README.md](README.md#what-each-node-needs). On VMs two
matter more than on one machine:

- `RELEASE_COOKIE`: **the same on every VM**, from your secret store, never
  in the image. `mix phx.gen.secret 32` makes one.
- `NODE_IP`: the VM's **private IP**. The node is named `acme@<NODE_IP>`, and
  other nodes connect to that address on port 9100.

Plus `DATABASE_URL`, `SECRET_KEY_BASE` and `PHX_HOST` (the same on every VM),
and whatever your app adds (the example's payment webhook needs
`PAYMENT_WEBHOOK_TOKEN`). Add `CLUSTER_DATABASE_URL` if `DATABASE_URL` goes
through PgBouncer in transaction mode.

## 3. Run the image

Build once (`docker build -t acme .`), push it to your registry, and on each
VM:

```sh
docker run -d --name acme --restart unless-stopped \
  -p 4000:4000 -p 9100:9100 \
  -e NODE_IP=10.0.0.5 \
  -e RELEASE_COOKIE=… -e DATABASE_URL=… -e SECRET_KEY_BASE=… \
  -e PHX_HOST=example.com \
  registry.example.com/acme:1.4.0
```

Publishing 9100 and setting `NODE_IP` to the VM's address is what lets a node
on another VM reach this one (inside the container, `hostname -i` would give
an address nobody else can reach).

Without Docker: the same release runs under systemd. Build it with
`MIX_ENV=prod mix release` on a machine of the same OS, copy
`_build/prod/rel/acme` over, and run `bin/server` with the same environment.

## 4. Migrations and rolling deploys

1. Run the migration **once**, from one place, before the new version
   starts: `docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… acme /app/bin/migrate`.
2. Replace the VMs **one at a time**: take it out of the load balancer (or let
   the health check do it), stop it, start the new image, wait for `/health`,
   next VM.
3. While you do, old and new versions run together. So a migration must work
   with **both**: add a column first, use it in the next release, remove the
   old one in the release after.

What happens to work in flight when a VM stops: its unfinished jobs are run
again by the other nodes (as in the proof), its WebSocket clients reconnect
to another VM, its cache is gone (and only a cache), and other nodes drop its
presence entries.

## 5. Checking it

From any VM, with the release running:

```sh
docker exec acme bin/acme rpc 'IO.inspect(Node.list())'    # the other VMs
docker exec acme bin/acme rpc 'IO.inspect(Oban.check_queue(queue: :default))'
```

`Node.list()` should show every other VM. If it doesn't: is 9100 open between
them, is `NODE_IP` the private IP, is the cookie the same, and can each VM
reach Postgres directly (not through a pooler — see `CLUSTER_DATABASE_URL`)?

## 6. Optional: TLS between nodes

Distribution is plain TCP on a private network. If your network isn't
trusted, Erlang can encrypt it: start the VM with `-proto_dist inet_tls` and
an `ssl_dist_optfile` pointing at each node's certificate
([Erlang docs](https://www.erlang.org/doc/apps/ssl/ssl_distribution.html)).
Add the flags in `rel/vm.args.eex`; the certificates come from your secret
store like the cookie does.
