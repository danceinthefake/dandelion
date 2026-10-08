defmodule Dandelion.Storage.Local do
  @moduledoc """
  Files in a directory. See `Dandelion.Storage` for what it is for and how to share it
  between nodes.

  `put/2` copies the source into a temporary file inside the directory, then renames
  it to its key: a rename within one directory is atomic, so a reader never sees half
  a file, and a crash leaves a temporary file (`tmp/…`), never a broken one.

  Layout: `<root>/<first two characters of the key>/<key>`, so no directory grows to
  millions of entries.
  """
  alias Dandelion.Storage

  @key_format ~r/\A[0-9a-f]{32}\z/

  @doc """
  Stores the file at `source` and returns its new key, its size and its SHA-256
  (lowercase hex). The source is left where it is (it is usually a `Plug.Upload`
  temporary file that is removed on its own).
  """
  @spec put(Path.t(), Path.t()) :: {:ok, Storage.stored()} | {:error, File.posix()}
  def put(root, source) do
    key = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    tmp = Path.join([root, "tmp", key])

    with :ok <- File.mkdir_p(Path.dirname(tmp)),
         {:ok, size, sha256} <- copy(source, tmp),
         final = location(root, key),
         :ok <- File.mkdir_p(Path.dirname(final)),
         :ok <- File.rename(tmp, final) do
      {:ok, %{key: key, size: size, sha256: sha256}}
    else
      {:error, _} = error ->
        File.rm(tmp)
        error
    end
  end

  @doc "Where the file for `key` is, for sending it. `{:error, :not_found}` if it is not there."
  @spec path(Path.t(), Storage.key()) :: {:ok, Path.t()} | {:error, :not_found}
  def path(root, key) do
    with true <- valid_key?(key),
         path = location(root, key),
         true <- File.regular?(path) do
      {:ok, path}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Removes the file. Removing one that is not there is fine."
  @spec delete(Path.t(), Storage.key()) :: :ok
  def delete(root, key) do
    if valid_key?(key), do: File.rm(location(root, key))
    :ok
  end

  @doc "Every key in the directory (for finding files no row points at)."
  @spec keys(Path.t()) :: [Storage.key()]
  def keys(root) do
    root
    |> Path.join("??/*")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.filter(&valid_key?/1)
  end

  @doc "Whether `key` has the shape of a key we make."
  def valid_key?(key), do: is_binary(key) and key =~ @key_format

  # -- inside ----------------------------------------------------------------------

  defp location(root, <<shard::binary-size(2), _::binary>> = key),
    do: Path.join([root, shard, key])

  # streams the copy, hashing as it goes: the file is read once
  defp copy(source, target) do
    with {:ok, out} <- File.open(target, [:write, :binary, :exclusive]) do
      try do
        source
        |> File.stream!(64 * 1024)
        |> Enum.reduce({:crypto.hash_init(:sha256), 0}, fn chunk, {hash, size} ->
          :ok = IO.binwrite(out, chunk)
          {:crypto.hash_update(hash, chunk), size + byte_size(chunk)}
        end)
        |> then(fn {hash, size} ->
          {:ok, size, hash |> :crypto.hash_final() |> Base.encode16(case: :lower)}
        end)
      rescue
        error in File.Error -> {:error, error.reason}
      after
        File.close(out)
      end
    end
  end
end
