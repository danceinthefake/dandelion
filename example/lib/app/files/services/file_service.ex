defmodule App.Files.Services.FileService do
  @moduledoc """
  Uploaded files. ≈ `service/files.go` over a bucket.

  The bytes go to the configured storage (`storage/0`: `Dandelion.Storage.Local`, a directory every
  node sees, or `Dandelion.Storage.S3`, a bucket); the row in
  `stored_files` says whose they are. A customer sees only their own files (`:not_found`
  for anyone else's); an admin sees all.

  Order matters: the file is written first, then the row. If the row can't be saved
  the file is removed; a crash in between leaves a file nothing points at (found with
  the adapter's `keys/1`), never a row that points at nothing.
  """
  alias App.Audit.Services.AuditService
  alias App.Files.Models.StoredFile
  alias App.Files.Services.ContentType
  alias Dandelion.Storage.Local
  alias Platform.Database.Repo
  alias Platform.Database.Repos.StoredFileRepo

  @max_name 255

  @type viewer :: %{id: integer(), role: String.t()}

  @doc "Where uploads are kept: `{adapter, its configuration}`; a directory unless `:storage` says otherwise."
  def storage, do: Application.get_env(:acme, :storage) || {Local, root()}

  @doc "The directory of the local adapter, and the largest file accepted, in bytes."
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
         {:ok, stored} <- put(path) do
      save(stored, type, filename, viewer)
    else
      {:error, :too_big} ->
        {:error, {:too_large, "a file can be at most #{max_bytes()} bytes"}}

      {:error, :unsupported} ->
        {:error, {:invalid, "only PNG, JPEG, PDF and plain text files are accepted"}}

      {:error, {:invalid, _}} = invalid ->
        invalid

      {:error, reason} when is_atom(reason) ->
        {:error, {:invalid, "can't read the upload: #{inspect(reason)}"}}

      {:error, _storage_down} ->
        {:error, {:unavailable, "the file storage is not answering: try again in a moment"}}
    end
  end

  def create(_other, _viewer),
    do: {:error, {:invalid, "send the file as multipart form data, in the field \"file\""}}

  defp put(path) do
    {adapter, conf} = storage()
    adapter.put(conf, path)
  end

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
        remove(stored.key)
        error
    end
  end

  @doc "A file and its bytes, as `{:file, path}` or `{:binary, bytes}`, to send."
  @spec get(integer(), viewer()) ::
          {:ok, StoredFile.t(), {:file, Path.t()} | {:binary, binary()}} | {:error, term()}
  def get(id, viewer) do
    {adapter, conf} = storage()

    with %StoredFile{} = file <- StoredFileRepo.get(id, scope(viewer)) || {:error, :not_found},
         {:ok, source} <- fetch(adapter, conf, file.storage_key) do
      {:ok, file, source}
    end
  end

  defp fetch(adapter, conf, key) do
    case adapter.fetch(conf, key) do
      {:error, reason} when reason != :not_found ->
        {:error, {:unavailable, "the file storage is not answering: try again in a moment"}}

      other ->
        other
    end
  end

  @spec list(viewer()) :: [StoredFile.t()]
  def list(viewer), do: StoredFileRepo.list(scope(viewer), 100)

  @doc "Removes the row, then the bytes."
  @spec delete(integer(), viewer()) :: :ok | {:error, :not_found}
  def delete(id, viewer) do
    result =
      Repo.transact(fn ->
        with %StoredFile{} = file <- StoredFileRepo.get(id, scope(viewer)) || {:error, :not_found},
             {:ok, _} <- StoredFileRepo.delete(file) do
          AuditService.record(AuditService.actor(viewer), "file.deleted", "file:#{id}", %{
            filename: file.filename,
            owner: file.user_id
          })

          {:ok, file}
        end
      end)

    with {:ok, file} <- result do
      remove(file.storage_key)
      :ok
    end
  end

  defp remove(key) do
    {adapter, conf} = storage()
    adapter.delete(conf, key)
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
