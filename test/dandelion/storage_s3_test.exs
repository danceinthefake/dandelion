defmodule Dandelion.StorageS3Test do
  use ExUnit.Case, async: true

  alias Dandelion.Storage.S3

  @moduletag :tmp_dir

  # A bucket in a process: what an S3-compatible server does with the five requests used.
  defp bucket(opts \\ []) do
    {:ok, objects} = Agent.start_link(fn -> %{} end)
    seen = :ets.new(:seen, [:public, :bag])

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      :ets.insert(
        seen,
        {conn.method, conn.request_path, Plug.Conn.get_req_header(conn, "authorization")}
      )

      key = conn.path_info |> tl() |> Enum.join("/")
      refuse = Keyword.get(opts, :refuse)

      cond do
        refuse && conn.method == "PUT" ->
          Plug.Conn.send_resp(conn, refuse, "AccessDenied")

        conn.method == "PUT" ->
          Agent.update(objects, &Map.put(&1, key, body))
          Plug.Conn.send_resp(conn, 200, "")

        conn.method == "DELETE" ->
          Agent.update(objects, &Map.delete(&1, key))
          Plug.Conn.send_resp(conn, 204, "")

        conn.method == "GET" and key == "" ->
          list(conn, objects)

        conn.method == "GET" ->
          case Agent.get(objects, &Map.fetch(&1, key)) do
            {:ok, b} -> Plug.Conn.send_resp(conn, 200, b)
            :error -> Plug.Conn.send_resp(conn, 404, "<Error><Code>NoSuchKey</Code></Error>")
          end
      end
    end

    conf = [
      endpoint: "http://s3.test",
      bucket: "up",
      access_key_id: "AK",
      secret_access_key: "SK",
      region: "eu-west-1",
      req_options: [plug: plug]
    ]

    {conf, objects, seen}
  end

  # two keys a page, to see the paging followed
  defp list(conn, objects) do
    all = objects |> Agent.get(&Map.keys/1) |> Enum.sort()

    token =
      conn.query_params
      |> then(fn _ -> Plug.Conn.fetch_query_params(conn).query_params["continuation-token"] end)

    rest = if token, do: Enum.drop_while(all, &(&1 <= token)), else: all
    {page, more} = Enum.split(rest, 2)

    next =
      if more != [],
        do: "<NextContinuationToken>#{List.last(page)}</NextContinuationToken>",
        else: ""

    xml =
      "<ListBucketResult>" <>
        Enum.map_join(page, &"<Contents><Key>#{&1}</Key></Contents>") <>
        next <> "</ListBucketResult>"

    Plug.Conn.send_resp(conn, 200, xml)
  end

  defp source(dir, content) do
    path = Path.join(dir, "upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  test "put stores the bytes under a random key, signed, at endpoint/bucket/key", %{tmp_dir: dir} do
    {conf, objects, seen} = bucket()

    assert {:ok, %{key: key, size: 11, sha256: sha}} = S3.put(conf, source(dir, "hello world"))
    assert key =~ ~r/\A[0-9a-f]{32}\z/
    assert sha == :crypto.hash(:sha256, "hello world") |> Base.encode16(case: :lower)
    assert Agent.get(objects, & &1) == %{key => "hello world"}

    assert [{"PUT", "/up/" <> ^key, [auth]}] = :ets.tab2list(seen)
    assert auth =~ "AWS4-HMAC-SHA256 Credential=AK/"
    assert auth =~ "/eu-west-1/s3/aws4_request"
  end

  test "fetch gives the bytes back; a key that is not there, or not ours, is not_found", %{
    tmp_dir: dir
  } do
    {conf, _objects, seen} = bucket()
    {:ok, %{key: key}} = S3.put(conf, source(dir, "bytes"))

    assert {:ok, {:binary, "bytes"}} = S3.fetch(conf, key)
    assert {:error, :not_found} = S3.fetch(conf, String.duplicate("0", 32))

    :ets.delete_all_objects(seen)
    assert {:error, :not_found} = S3.fetch(conf, "../../etc/passwd")
    assert :ets.tab2list(seen) == [], "a key of the wrong shape never reaches the bucket"
  end

  test "delete removes it, and removing one that is not there is fine", %{tmp_dir: dir} do
    {conf, objects, _} = bucket()
    {:ok, %{key: key}} = S3.put(conf, source(dir, "x"))

    assert :ok = S3.delete(conf, key)
    assert Agent.get(objects, & &1) == %{}
    assert :ok = S3.delete(conf, key)
    assert :ok = S3.delete(conf, "not a key")
  end

  test "keys follows the pages", %{tmp_dir: dir} do
    {conf, _, _} = bucket()
    stored = for i <- 1..5, do: elem(S3.put(conf, source(dir, "#{i}")), 1).key
    assert Enum.sort(S3.keys(conf)) == Enum.sort(stored)
  end

  test "a bucket that refuses the file is an error, not a key", %{tmp_dir: dir} do
    {conf, objects, _} = bucket(refuse: 403)
    assert {:error, {:bucket_refused, 403}} = S3.put(conf, source(dir, "x"))
    assert Agent.get(objects, & &1) == %{}
  end

  test "a server that is not there is an error, quickly" do
    conf = [
      endpoint: "http://127.0.0.1:1",
      bucket: "up",
      access_key_id: "a",
      secret_access_key: "b",
      timeout: 500
    ]

    assert {:error, _} = S3.fetch(conf, String.duplicate("a", 32))
  end
end
