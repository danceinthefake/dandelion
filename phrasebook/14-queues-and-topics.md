# 14. Queues and topics

What you'd reach for in Go: **Cloud Tasks / asynq / RabbitMQ** for work to do
later, **Google Pub/Sub / Kafka / SNS** for one event with several listeners,
**SQS FIFO / Kafka partitions** when order matters. Here all three are rows in
the Postgres you already have, run by [Oban](https://hexdocs.pm/oban).

| You used | Here |
|---|---|
| Cloud Tasks, asynq, a RabbitMQ queue | an Oban worker (`App.<Domain>.Workers.*`) |
| Google Pub/Sub topic + subscriptions, Kafka consumer groups | `Platform.PubSub`: one job per subscriber |
| SQS FIFO message group, Kafka partition key, Pub/Sub ordering key | `Platform.Queue.Ordered`: order per key |

## A queue: work to do later

```go
task := asynq.NewTask("email:confirm", payload)
client.Enqueue(task, asynq.MaxRetry(5))
```

```elixir
defmodule App.Shop.Workers.SendOrderConfirmation do
  use Oban.Worker, queue: :default, max_attempts: 5

  def perform(%Oban.Job{args: args}), do: ...      # :ok, {:error, _}, or a crash: retried with backoff
end

Oban.insert(SendOrderConfirmation.new(%{order_id: 42}))
```

A job is a row. It survives a restart, runs on any node, is retried if it
fails, and is **run again if its node dies mid-job** (the lifeline plugin
gives it back; [`lib/platform/queue.ex`](../example/lib/platform/queue.ex)). So
a worker must be safe to run twice — the same rule as every queue that
promises "at least once".

## A topic: one event, several listeners

```go
topic.Publish(ctx, &pubsub.Message{Data: data})  // each subscription gets a copy
```

```elixir
# in the transaction that saves the order
PubSub.publish("order.created", %{"order_id" => order.id, "customer_email" => order.customer_email})
```

`Platform.PubSub` ([`pubsub.ex`](../example/lib/platform/pubsub.ex)) holds the
list of subscribers per topic, in one place like a crontab. `publish/2` adds
one job **per subscriber**, so each is retried on its own and a slow or
failing one doesn't hold back the others.

The big difference from an external broker: you publish **inside the
transaction** that saves the data.

```elixir
Repo.transact(fn ->
  with {:ok, order} <- insert_order(params) do
    PubSub.publish("order.created", ...)     # saved together with the order, or not at all
    {:ok, order}
  end
end)
```

With Kafka or Pub/Sub that is the *dual-write problem*: save the order,
crash before publishing, and the event is lost — which is why people build an
outbox table and a relay process. Here the outbox **is** the queue
([`order_service.ex`](../example/lib/app/shop/services/order_service.ex)).

A subscriber that counts must survive running twice:
[`update_customer_stats.ex`](../example/lib/app/shop/workers/update_customer_stats.ex)
recounts the customer's orders instead of adding one.

## Order per key

Queues don't keep order. When events of one order must run in the order they
arrived (a payment, then its refund), use the ordered queue:

```go
// SQS FIFO
sqs.SendMessage(&sqs.SendMessageInput{MessageGroupId: aws.String("order:42"), ...})
```

```elixir
Ordered.insert(ProcessPaymentEvent.new(args), "order:42")     # in the webhook's transaction

def perform(job) do
  with :ok <- Ordered.turn(job), do: apply_event(job.args)    # waits while an earlier one is unfinished
end
```

- The events of **one key** run one at a time, in arrival order; other keys
  run in parallel on all nodes.
- **Arrival order is Postgres's order**, not the servers' clocks: the insert
  takes a lock on the key, so job 102 can't become visible before job 101.
- A failing job **blocks its key** while it retries (like a Kafka partition).
  Out of attempts, it stops blocking.
- The provider's retries are dropped: the job is unique on the event's id.

([`payment_handler.ex`](../example/lib/app/shop/handlers/payment_handler.ex),
[`process_payment_event.ex`](../example/lib/app/shop/workers/process_payment_event.ex),
[`lib/platform/queue/ordered.ex`](../example/lib/platform/queue/ordered.ex).)

## "I still need a real broker"

Two cases: **other systems send you events** (a partner's Kafka, a cloud
queue), or you need **Kafka-style replay** of months of events at high volume.
For the first, consume the broker with
[Broadway](https://hexdocs.pm/broadway) — it reads RabbitMQ, SQS, Kafka or
Pub/Sub with back-pressure and batching, and each message can enqueue an Oban
job. For the second, keep Kafka; an events table in Postgres only covers the
modest version.

**Why:** a broker is a second database with its own failure modes. When the
queue is in the database that holds your data, "saved but not published"
can't happen, and there is one thing to back up.
