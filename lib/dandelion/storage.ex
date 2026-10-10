defmodule Dandelion.Storage do
  @moduledoc """
  Keeping uploaded files. ≈ a Cloud Storage / S3 bucket — here a directory on disk.

  The bytes live in files; **what a file is** (whose it is, its name, its type, its
  size) lives in a row of your own table, in Postgres. This module only does the
  files: `Dandelion.Storage.Local`.

      {:ok, stored} = Dandelion.Storage.Local.put(root, "/tmp/plug-upload-123")
      # %{key: "9f2c…", size: 20_481, sha256: "…"}

      {:ok, path} = Dandelion.Storage.Local.path(root, stored.key)   # to send it
      :ok = Dandelion.Storage.Local.delete(root, stored.key)

  **One directory every node can see.** A file written by one node must be readable by
  the others, because the load balancer sends the download anywhere. On one machine
  that is just a directory; on several it must be a shared mount (NFS, EFS, a
  Kubernetes `ReadWriteMany` volume, a Docker volume on one host). If it is not shared,
  a file is only found on the node that took it — see "Not here".

  Keys are random (128 bits of hex), never made from what the client called the file,
  so no name can reach outside the directory, and two files never collide.

  **A bucket instead of a directory:** `Dandelion.Storage.S3` keeps the bytes in any
  S3-compatible bucket (AWS S3, Google Cloud Storage's interoperability endpoint, Cloudflare R2,
  Backblaze B2, Garage, SeaweedFS, Ceph…): nothing has to be mounted on the nodes. It has the
  same functions (the callbacks below), so a service picks one by configuration.

  **Not here:** a native Google Cloud Storage adapter (its own API and sign-in; the S3 one
  reaches it through the interoperability endpoint); resumable or multi-gigabyte uploads; removing
  files that no row points at (a crash between writing the file and saving the row
  leaves one; `Dandelion.Storage.Local.keys/1` lists what is there, for a sweep).
  """

  @type key :: String.t()
  @type stored :: %{key: key(), size: non_neg_integer(), sha256: String.t()}

  @doc """
  An adapter is a module with these four functions, each taking the adapter's own
  configuration (`Local`: the directory; `S3`: a keyword list) first:

  - `put/2`: stores the file at a path, under a new random key;
  - `fetch/2`: what to send for a key, as `{:file, path}` or `{:binary, bytes}` (both are
    what `Phoenix.Controller.send_download/3` takes), or `{:error, :not_found}`;
  - `delete/2`: removes it (one that is not there is fine);
  - `keys/1`: every key held (for finding files no row points at).
  """
  @callback put(term(), Path.t()) :: {:ok, stored()} | {:error, term()}
  @callback fetch(term(), key()) ::
              {:ok, {:file, Path.t()} | {:binary, binary()}} | {:error, :not_found | term()}
  @callback delete(term(), key()) :: :ok | {:error, term()}
  @callback keys(term()) :: [key()] | {:error, term()}
end
