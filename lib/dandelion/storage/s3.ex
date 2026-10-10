defmodule Dandelion.Storage.S3 do
  @moduledoc """
  Files in an S3-compatible bucket. See `Dandelion.Storage` for what it is for.

      conf = [
        endpoint: "https://s3.eu-west-1.amazonaws.com",   # or http://garage:3900, https://storage.googleapis.com…
        bucket: "my-uploads",
        region: "eu-west-1",
        access_key_id: "…",
        secret_access_key: "…"
      ]

      {:ok, %{key: key}} = Dandelion.Storage.S3.put(conf, "/tmp/plug-upload-123")
      {:ok, {:binary, bytes}} = Dandelion.Storage.S3.fetch(conf, key)

  Requests are signed with Signature V4 (`Req`'s `:aws_sigv4`) and use **path-style** URLs
  (`endpoint/bucket/key`), which every S3-compatible server accepts. Objects are held under
  random keys (128 bits of hex), as in `Dandelion.Storage.Local`; nothing a client sent
  reaches the object name.

  Each call is one request with a timeout (`:timeout`, 15 s) and **no retry here**: a
  failure is returned, and the caller (a request: the client asks again with its idempotency
  key; a job: the queue retries) decides. `put/2` checks the answer: a bucket that refuses
  the file is an `{:error, _}`, never a stored key.

  A file is read whole into memory to be sent or received (files are small here: the
  example's limit is 5 MB). Multipart upload, streaming and presigned URLs are not here.
  Optional dependency: add `{:req, "~> 0.5"}` to use this module.
  """
  alias Dandelion.Storage

  @behaviour Storage

  @key_format ~r/\A[0-9a-f]{32}\z/

  @impl true
  def put(conf, source) do
    key = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

    with {:ok, body} <- File.read(source),
         {:ok, %{status: status}} when status in 200..299 <-
           request(conf, :put, key,
             body: body,
             headers: [{"content-type", "application/octet-stream"}]
           ) do
      {:ok,
       %{
         key: key,
         size: byte_size(body),
         sha256: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
       }}
    else
      {:ok, %{status: status}} -> {:error, {:bucket_refused, status}}
      {:error, _} = error -> error
    end
  end

  @impl true
  def fetch(conf, key) do
    with true <- valid_key?(key),
         {:ok, %{status: 200, body: body}} <- request(conf, :get, key) do
      {:ok, {:binary, body}}
    else
      false -> {:error, :not_found}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:bucket_refused, status}}
      {:error, _} = error -> error
    end
  end

  @impl true
  def delete(conf, key) do
    if valid_key?(key) do
      case request(conf, :delete, key) do
        {:ok, %{status: status}} when status in [200, 204, 404] -> :ok
        {:ok, %{status: status}} -> {:error, {:bucket_refused, status}}
        {:error, _} = error -> error
      end
    else
      :ok
    end
  end

  @impl true
  def keys(conf), do: list(conf, nil, [])

  def valid_key?(key), do: is_binary(key) and key =~ @key_format

  # -- inside ----------------------------------------------------------------------

  # ListObjectsV2, a page at a time (the answer is XML: only <Key> and the paging are read)
  defp list(conf, token, acc) do
    params = [{"list-type", "2"}] ++ if(token, do: [{"continuation-token", token}], else: [])

    case request(conf, :get, nil, params: params) do
      {:ok, %{status: 200, body: xml}} ->
        keys = Regex.scan(~r{<Key>([^<]+)</Key>}, xml, capture: :all_but_first) |> List.flatten()
        acc = acc ++ Enum.filter(keys, &valid_key?/1)

        case Regex.run(~r{<NextContinuationToken>([^<]+)</NextContinuationToken>}, xml) do
          [_, next] -> list(conf, next, acc)
          nil -> acc
        end

      {:ok, %{status: status}} ->
        {:error, {:bucket_refused, status}}

      {:error, _} = error ->
        error
    end
  end

  defp request(conf, method, key, opts \\ []) do
    base =
      String.trim_trailing(Keyword.fetch!(conf, :endpoint), "/") <>
        "/" <> Keyword.fetch!(conf, :bucket)

    url = if key, do: base <> "/" <> key, else: base

    [
      method: method,
      url: url,
      aws_sigv4: [
        access_key_id: Keyword.fetch!(conf, :access_key_id),
        secret_access_key: Keyword.fetch!(conf, :secret_access_key),
        service: :s3,
        region: Keyword.get(conf, :region, "us-east-1")
      ],
      retry: false,
      decode_body: false,
      receive_timeout: Keyword.get(conf, :timeout, 15_000)
    ]
    |> Keyword.merge(opts)
    |> Keyword.merge(Keyword.get(conf, :req_options, []))
    |> Req.request()
  end
end
