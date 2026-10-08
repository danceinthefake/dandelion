defmodule App.Files.Services.FileService do
  @moduledoc """
  Uploaded files. ≈ `service/files.go` over a bucket.

  The bytes go to `Dandelion.Storage.Local` (a directory every node sees); the row in
  `stored_files` says whose they are. A customer sees only their own files (`:not_found`
  for anyone else's); an admin sees all.

  Order matters: the file is written first, then the row. If the row can't be saved
  the file is removed; a crash in between leaves a file nothing points at (found with
  `Dandelion.Storage.Local.keys/1`), never a row that points at nothing.
  """
  alias App.Files.Models.StoredFile
  alias App.Files.Services.ContentType
  alias Dandelion.Storage.Local
  alias Platform.Database.Repos.StoredFileRepo

  @max_name 255

  @type viewer :: %{id: integer(), role: String.t()}

  @doc "Where uploads are kept, and the largest file accepted, in bytes."
  def root, do: Application.fetch_env!(:acme, :uploads_dir)
  def max_bytes, do: Application.fetch_env!(:acme, :upload_max_bytes)

  @doc """
  Keeps an upload (`%Plug.Upload{}`) for `viewer`. Checks the size, and that the bytes
  are a PNG, JPEG, PDF or text file.
  """
  @spec create(term(), viewer()) :: {:ok, StoredFile.t()} | {:error, term()}
  def create(%Plug.Upload{path: path, filename: filename}, viewer) do
    with {:ok, %{size: size}} <- File.stat(path),
         :ok <- check_size(size),
         {:ok, type} <- check_type(path),
         {:ok, stored} <- Local.put(root(), path) do
      save(stored, type, filename, viewer)
    else
      {:error, :too_big} ->
        {:error, {:too_large, "a file can be at most #{max_bytes()} bytes"}}

      {:error, :unsupported} ->
        {:error, {:invalid, "only PNG, JPEG, PDF and plain text files are accepted"}}

      {:error, reason} ->
        {:error, {:invalid, "can't read the upload: #{inspect(reason)}"}}
    end
  end

  def create(_other, _viewer),
    do: {:error, {:invalid, "send the file as multipart form data, in the field \"file\""}}

  defp save(stored, type, filename, viewer) do
    attrs = [
      user_id: viewer.id,
      filename: clean_name(filename),
      content_type: type,
      size: stored.size,
      sha256: stored.sha256,
      storage_key: stored.key
    ]

    case StoredFileRepo.insert(attrs) do
      {:ok, file} ->
        {:ok, file}

      {:error, _} = error ->
        Local.delete(root(), stored.key)
        error
    end
  end

  @doc "A file and where its bytes are, to send it."
  @spec get(integer(), viewer()) :: {:ok, StoredFile.t(), Path.t()} | {:error, :not_found}
  def get(id, viewer) do
    with %StoredFile{} = file <- StoredFileRepo.get(id, scope(viewer)) || {:error, :not_found},
         {:ok, path} <- Local.path(root(), file.storage_key) do
      {:ok, file, path}
    end
  end

  @spec list(viewer()) :: [StoredFile.t()]
  def list(viewer), do: StoredFileRepo.list(scope(viewer), 100)

  @doc "Removes the row, then the bytes."
  @spec delete(integer(), viewer()) :: :ok | {:error, :not_found}
  def delete(id, viewer) do
    with %StoredFile{} = file <- StoredFileRepo.get(id, scope(viewer)) || {:error, :not_found},
         {:ok, _} <- StoredFileRepo.delete(file) do
      Local.delete(root(), file.storage_key)
      :ok
    end
  end

  defp scope(%{role: "admin"}), do: :all
  defp scope(%{id: id}), do: {:user, id}

  defp check_size(size) when size > 0 and size <= 5_000_000, do: check_configured(size)
  defp check_size(0), do: {:error, {:invalid, "the file is empty"}}
  defp check_size(_), do: {:error, :too_big}

  defp check_configured(size), do: if(size <= max_bytes(), do: :ok, else: {:error, :too_big})

  defp check_type(path) do
    case ContentType.detect(path) do
      {:ok, type} -> {:ok, type}
      :unknown -> {:error, :unsupported}
    end
  end

  # only for showing it back: no path parts, no control characters, not too long
  defp clean_name(name) do
    name
    |> to_string()
    |> String.replace("\\", "/")
    |> Path.basename()
    |> String.replace(~r/[[:cntrl:]]/u, "")
    |> String.slice(0, @max_name)
    |> case do
      "" -> "file"
      clean -> clean
    end
  end
end
