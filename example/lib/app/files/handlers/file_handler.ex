defmodule App.Files.Handlers.FileHandler do
  @moduledoc """
  HTTP handlers for uploaded files. Every route needs a login (the router); a customer
  sees only their own files. The download is always an attachment, with the type we
  worked out from the bytes and `nosniff`: a file someone uploaded is never run or shown
  by a browser as a page of ours.
  """
  use Platform.Web, :handler

  alias App.Files.Handlers.FileJSON
  alias App.Files.Services.FileService

  action_fallback Platform.Web.FallbackHandler

  # POST /api/files   (multipart form, the file in the field "file")
  def create(conn, params) do
    with {:ok, file} <- FileService.create(params["file"], viewer(conn)) do
      conn |> put_status(:created) |> json(FileJSON.file(file))
    end
  end

  # GET /api/files
  def index(conn, _params),
    do: json(conn, %{files: Enum.map(FileService.list(viewer(conn)), &FileJSON.file/1)})

  # GET /api/files/:id  (the bytes)
  def show(conn, %{"id" => id}) do
    with {:ok, id} <- id(id),
         {:ok, file, path} <- FileService.get(id, viewer(conn)) do
      conn
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("etag", ~s("#{file.sha256}"))
      |> send_download({:file, path}, filename: file.filename, content_type: file.content_type)
    end
  end

  # DELETE /api/files/:id
  def delete(conn, %{"id" => id}) do
    with {:ok, id} <- id(id),
         :ok <- FileService.delete(id, viewer(conn)) do
      send_resp(conn, :no_content, "")
    end
  end

  defp viewer(conn), do: conn.assigns.current_user

  defp id(value) do
    case Integer.parse(value) do
      {id, ""} when id in 1..9_223_372_036_854_775_807//1 -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end
end
