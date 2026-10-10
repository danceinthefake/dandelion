# 14. Queues and topics

In Go, you use Cloud Tasks, asynq, or RabbitMQ for work to do later. You use Google Pub/Sub, Kafka, or SNS for one event with several listeners. You use SQS FIFO or Kafka partitions when order matters. Here, all three are rows in the Postgres that you already have. [Oban](https://hexdocs.pm/oban) runs them.

| You used | Here |
|---|---|
| Cloud Tasks, asynq, a RabbitMQ queue | an Oban worker (`App.<Domain>.Workers.*`) |
| Google Pub/Sub topic + subscriptions, Kafka consumer groups | `Platform.PubSub`: one job for each subscriber |
| SQS FIFO message group, Kafka partition key, Pub/Sub ordering key | `Dandelion.Queue.Ordered`: order for each key |

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

A job is a row. It survives a restart and runs on any node. If it fails, the service retries it. If its node dies in the middle of the job, the service runs the job again. The lifeline plugin gives the job back. [`Dandelion.Queue`](../lib/dandelion/queue.ex) sets up the plugin, and [`lib/platform/queue.ex`](../example/lib/platform/queue.ex) uses it. A worker must therefore be safe to run twice. This is the same rule as for every queue that promises "at least once".

## A topic: one event, several listeners

```go
topic.Publish(ctx, &pubsub.Message{Data: data})  // each subscription gets a copy
```

```elixir
# in the transaction that saves the order
PubSub.publish("order.created", %{"order_id" => order.id, "customer_email" => order.customer_email})
```

`Platform.PubSub` ([`pubsub.ex`](../example/lib/platform/pubsub.ex)) holds the list of subscribers for each topic, in one place like a crontab. The mechanism is [`Dandelion.PubSub`](../lib/dandelion/pubsub.ex). `publish/2` adds one job for each subscriber. The service retries each job on its own, and a slow or failing job does not hold back the others.

This is the big difference from an external broker: you publish inside the transaction that saves the data.

```elixir
Repo.transact(fn ->
  with {:ok, order} <- insert_order(params) do
    PubSub.publish("order.created", ...)     # saved together with the order, or not at all
    {:ok, order}
  end
end)
```

With Kafka or Pub/Sub, this is the dual-write problem. You save the order, the service crashes before it publishes, and the event is lost. This is the reason that people build an outbox table and a relay process. Here, the outbox is the queue ([`order_service.ex`](../example/lib/app/shop/services/order_service.ex)).

A subscriber that counts must survive two runs:
[`update_customer_stats.ex`](../example/lib/app/shop/workers/update_customer_stats.ex)
recounts the customer's orders instead of adding one.

## Order per key

Queues do not keep order. Use the ordered queue when the events of one order must run in the order that they arrived (a payment and then its refund):

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

- The events of one key run one at a time, in arrival order. Other keys run in parallel on all nodes.
- Arrival order is the order of Postgres and not the clocks of the servers. The insert takes a lock on the key, so job 102 cannot become visible before job 101.
- A failing job blocks its key while it retries, like a Kafka partition. When the job has no attempts left, it stops blocking.
- The service drops the retries of the provider. The job is unique on the id of the event.

([`payment_handler.ex`](../example/lib/app/shop/handlers/payment_handler.ex),
[`process_payment_event.ex`](../example/lib/app/shop/workers/process_payment_event.ex),
[`Dandelion.Queue.Ordered`](../lib/dandelion/queue/ordered.ex).)

## "I still need a real broker"

Two cases exist. In the first case, other systems send you events (the Kafka of a partner or a cloud queue). In the second case, you need Kafka-style replay of months of events at high volume. For the first case, consume the broker with [Broadway](https://hexdocs.pm/broadway). It reads RabbitMQ, SQS, Kafka, or Pub/Sub with back-pressure and batching, and each message can queue an Oban job. For the second case, keep Kafka. An events table in Postgres covers only the modest version.

**Why:** A broker is a second database with its own failure modes. When the queue is in the database that holds your data, "saved but not published" cannot happen. You also have one thing to back up.
