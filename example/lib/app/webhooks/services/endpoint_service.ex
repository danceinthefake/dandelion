defmodule App.Webhooks.Services.EndpointService do
  @moduledoc """
  Who is told about what. ≈ Stripe's "webhook endpoints" API. Only admins manage
  them (the router says so); the secret is shown once, when the endpoint is made.
  """
  alias App.Webhooks.Models.Endpoint
  alias Platform.Database.Repos.EndpointRepo

  # the events a receiver may ask for: the topics Platform.PubSub has a webhook
  # subscriber for
  @events ~w(order.created)

  def events, do: @events

  @spec create(map()) :: {:ok, Endpoint.t()} | {:error, Ecto.Changeset.t()}
  def create(params), do: params |> Endpoint.create_changeset(@events) |> EndpointRepo.insert()

  @spec list() :: [Endpoint.t()]
  def list, do: EndpointRepo.list()

  @spec get(integer()) :: {:ok, Endpoint.t()} | {:error, :not_found}
  def get(id) do
    case EndpointRepo.get(id) do
      nil -> {:error, :not_found}
      endpoint -> {:ok, endpoint}
    end
  end

  @spec delete(integer()) :: :ok | {:error, :not_found}
  def delete(id) do
    with {:ok, endpoint} <- get(id), {:ok, _} <- EndpointRepo.delete(endpoint), do: :ok
  end

  @doc "The endpoints to tell about `event`."
  def subscribers(event), do: EndpointRepo.active_for(event)

  @doc "Stops sending to an endpoint (its receiver said it is gone)."
  def deactivate(%Endpoint{} = endpoint), do: EndpointRepo.deactivate(endpoint)
end
