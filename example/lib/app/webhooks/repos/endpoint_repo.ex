defmodule Platform.Database.Repos.EndpointRepo do
  @moduledoc "Webhook endpoint queries, and nothing else."
  import Ecto.Query

  alias App.Webhooks.Models.Endpoint
  alias Platform.Database.Repo

  def insert(%Ecto.Changeset{} = changeset), do: Repo.insert(changeset)

  def get(id), do: Repo.get(Endpoint, id)

  def list, do: Endpoint |> order_by(:id) |> Repo.all()

  @doc "Active endpoints that asked for `event`."
  def active_for(event) do
    Endpoint |> where([e], e.active and ^event in e.events) |> order_by(:id) |> Repo.all()
  end

  def deactivate(%Endpoint{} = endpoint) do
    endpoint |> Ecto.Changeset.change(active: false) |> Repo.update()
  end

  def delete(%Endpoint{} = endpoint), do: Repo.delete(endpoint)
end
