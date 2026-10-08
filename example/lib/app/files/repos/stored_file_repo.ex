defmodule Platform.Database.Repos.StoredFileRepo do
  @moduledoc "Stored file queries, and nothing else."
  import Ecto.Query

  alias App.Files.Models.StoredFile
  alias Platform.Database.Repo

  def insert(attrs), do: attrs |> StoredFile.create_changeset() |> Repo.insert()

  @doc "A file by id, within `scope`: `:all`, or `{:user, id}` for one customer's."
  def get(id, scope \\ :all) do
    StoredFile |> where(id: ^id) |> scoped(scope) |> Repo.one()
  end

  def list(scope, limit) do
    StoredFile |> scoped(scope) |> order_by(desc: :id) |> limit(^limit) |> Repo.all()
  end

  def delete(%StoredFile{} = file), do: Repo.delete(file)

  defp scoped(query, :all), do: query
  defp scoped(query, {:user, id}), do: where(query, user_id: ^id)
end
