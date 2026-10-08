defmodule App.Webhooks.Services.EndpointService do
  @moduledoc """
  Who is told about what. ≈ Stripe's "webhook endpoints" API. Only admins manage
  them (the router says so); the secret is shown once, when the endpoint is made.
  """
  alias App.Audit.Services.AuditService
  alias App.Webhooks.Models.Endpoint
  alias Platform.Database.Repo
  alias Platform.Database.Repos.EndpointRepo

  # the events a receiver may ask for: the topics Platform.PubSub has a webhook
  # subscriber for
  @events ~w(order.created)

  def events, do: @events

  @doc "Registers an endpoint, and records who did (never its secret)."
  @spec create(map(), AuditService.viewer()) :: {:ok, Endpoint.t()} | {:error, Ecto.Changeset.t()}
  def create(params, viewer \\ nil) do
    Repo.transact(fn ->
      with {:ok, endpoint} <-
             params |> Endpoint.create_changeset(@events) |> EndpointRepo.insert() do
        AuditService.record(
          AuditService.actor(viewer),
          "webhook.created",
          "webhook:#{endpoint.id}",
          %{
            url: endpoint.url,
            events: endpoint.events
          }
        )

        {:ok, endpoint}
      end
    end)
  end

  @spec list() :: [Endpoint.t()]
  def list, do: EndpointRepo.list()

  @spec get(integer()) :: {:ok, Endpoint.t()} | {:error, :not_found}
  def get(id) do
    case EndpointRepo.get(id) do
      nil -> {:error, :not_found}
      endpoint -> {:ok, endpoint}
    end
  end

  @spec delete(integer(), AuditService.viewer()) :: :ok | {:error, :not_found}
  def delete(id, viewer \\ nil) do
    result =
      Repo.transact(fn ->
        with {:ok, endpoint} <- get(id), {:ok, _} <- EndpointRepo.delete(endpoint) do
          AuditService.record(AuditService.actor(viewer), "webhook.deleted", "webhook:#{id}", %{
            url: endpoint.url
          })

          {:ok, endpoint}
        end
      end)

    with {:ok, _} <- result, do: :ok
  end

  @doc "The endpoints to tell about `event`."
  def subscribers(event), do: EndpointRepo.active_for(event)

  @doc "Stops sending to an endpoint (its receiver said it is gone)."
  def deactivate(%Endpoint{} = endpoint), do: EndpointRepo.deactivate(endpoint)
end
