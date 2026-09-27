defmodule ShopWeb.Handlers.FallbackHandler do
  @moduledoc """
  Turns service errors into HTTP responses — the one place that maps
  errors to status codes (≈ a Go `writeError(w, err)` helper).

      {:error, %Ecto.Changeset{}}    → 422 {"errors": {"field": ["message"]}}
      {:error, :not_found}           → 404
      {:error, {:conflict, message}} → 409
      {:error, {:invalid, message}}  → 400
  """
  use ShopWeb, :handler

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors(changeset)})
  end

  def call(conn, {:error, :not_found}), do: error(conn, :not_found, "not found")
  def call(conn, {:error, {:conflict, message}}), do: error(conn, :conflict, message)
  def call(conn, {:error, {:invalid, message}}), do: error(conn, :bad_request, message)

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})

  # {"customer_email": ["can't be blank"], "items": [{}, {"quantity": ["must be greater than 0"]}]}
  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
