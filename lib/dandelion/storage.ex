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

  **Not here:** an S3 or Google Cloud Storage adapter (a second module with the same
  three functions would be the place); resumable or multi-gigabyte uploads; removing
  files that no row points at (a crash between writing the file and saving the row
  leaves one; `Dandelion.Storage.Local.keys/1` lists what is there, for a sweep).
  """

  @type key :: String.t()
  @type stored :: %{key: key(), size: non_neg_integer(), sha256: String.t()}
end
