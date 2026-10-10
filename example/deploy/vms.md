# Running on N VMs

> This guide is not tested on real VMs. The proof in `cluster-proof.sh` runs three containers on one machine. Each step below is what those three containers do, written out for machines.

The shape is N VMs on a private network. Each VM runs the same image. All VMs talk to one Postgres. A load balancer in front is the only way in.

```
internet → load balancer ─┬─► vm1 :4000 ┐
                          ├─► vm2 :4000 ├─ 9100 between the VMs ─ Postgres (private)
                          └─► vm3 :4000 ┘
```

## 1. Network

- Put the VMs on a private network with no public IPs.
- Set the firewall on each VM:
  - Open 9100 (Erlang distribution) only to the other app VMs. Anyone who reaches it with the cookie can run any code on the node.
  - Open 4000 (HTTP) only to the load balancer.
  - Open Postgres only to the VMs.
- Use `GET /health` as the health probe of the load balancer. It answers 200 when the node and its database connection are good. Otherwise it answers 503.
- Keep the idle timeout of the load balancer above one minute. Let it pass WebSocket upgrades on `/socket` (the live feed). `nginx.conf` here shows the headers.

## 2. What each VM needs

The variables are in [README.md](README.md#what-each-node-needs). Two variables matter more on VMs than on one machine:

- `RELEASE_COOKIE` must be the same on every VM. Take it from your secret store. Never put it in the image. `mix phx.gen.secret 32` makes one.
- `NODE_IP` is the private IP of the VM. The node is named `acme@<NODE_IP>`, and other nodes connect to that address on port 9100.

You also need `DATABASE_URL`, `SECRET_KEY_BASE`, and `PHX_HOST`. They are the same on every VM. Add what your app needs. For example, the payment webhook of the example needs `PAYMENT_WEBHOOK_TOKEN`. If `DATABASE_URL` goes through PgBouncer in transaction mode, add `CLUSTER_DATABASE_URL`.

## 3. Run the image

Build the image one time (`docker build -t acme .`) and push it to your registry. Then run this command on each VM:

```sh
docker run -d --name acme --restart unless-stopped \
  -p 4000:4000 -p 9100:9100 \
  -e NODE_IP=10.0.0.5 \
  -e RELEASE_COOKIE=… -e DATABASE_URL=… -e SECRET_KEY_BASE=… \
  -e PHX_HOST=example.com \
  registry.example.com/acme:1.4.0
```

You publish 9100 and set `NODE_IP` to the address of the VM. A node on another VM can then reach this node. Inside the container, `hostname -i` gives an address that nobody else can reach.

Without Docker, the same release runs under systemd. Build it with `MIX_ENV=prod mix release` on a machine with the same OS. Copy `_build/prod/rel/acme` to the VM. Run `bin/server` with the same environment.

## 4. Migrations and rolling deploys

1. Run the migration one time, from one place, before the new version starts: `docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… acme /app/bin/migrate`.
2. Replace the VMs one at a time. Take the VM out of the load balancer (or let the health probe do it). Stop it, start the new image, and wait for `/health`. Then go to the next VM.
3. During the deploy, old and new versions run together. A migration must therefore work with both versions. Add a column first. Use it in the next release. Remove the old column in the release after that.

This is what happens to work in flight when a VM stops. The other nodes run its unfinished jobs again, as in the proof. Its WebSocket clients reconnect to another VM. Its cache is gone, and it was only a cache. The other nodes drop its presence entries.

## 5. Make sure that it works

Run these commands from any VM while the release runs:

```sh
docker exec acme bin/acme rpc 'IO.inspect(Node.list())'    # the other VMs
docker exec acme bin/acme rpc 'IO.inspect(Oban.check_queue(queue: :default))'
```

`Node.list()` must show every other VM. If it does not, ask these questions:
- Is 9100 open between the VMs?
- Is `NODE_IP` the private IP?
- Is the cookie the same?
- Can each VM reach Postgres directly, and not through a pooler? See `CLUSTER_DATABASE_URL`.

## 6. Optional: TLS between nodes

Distribution is plain TCP on a private network. If you do not trust your network, Erlang can encrypt the traffic. Start the VM with `-proto_dist inet_tls` and an `ssl_dist_optfile` that points at the certificate of each node ([Erlang docs](https://www.erlang.org/doc/apps/ssl/ssl_distribution.html)). Add the flags in `rel/vm.args.eex`. The certificates come from your secret store, as the cookie does.
