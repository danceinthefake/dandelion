defmodule App.Shop.Workers.UpdateCustomerStats do
  @moduledoc """
  Subscriber of `order.created` (`Platform.PubSub`): keeps the customer's
  order count.

  It **recounts** instead of adding one. Delivery is at least once, so
  "add one" would count an order twice when the job runs again; a recount
  gives the same answer however many times it runs.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Platform.Database.Repos.CustomerRepo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payload" => %{"customer_email" => email}}}) do
    CustomerRepo.refresh_orders_count(email)
    :ok
  end
end
