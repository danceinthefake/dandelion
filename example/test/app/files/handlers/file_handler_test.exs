defmodule App.Files.Handlers.FileHandlerTest do
  # one uploads directory for all the tests: they run one at a time
  use Platform.ConnCase, async: false

  import App.Accounts.Fixtures
  import App.Files.Fixtures

  setup %{conn: conn} do
    clean_uploads()
    user = user_fixture()
    {:ok, conn: log_in(conn, user), user: user}
  end

  defp upload!(conn, content, name \\ "pic.png") do
    conn
    |> post("/api/files", %{"file" => upload(content, name, "image/png")})
    |> json_response(201)
  end

  test "a logged-in user uploads a file and downloads the same bytes", %{conn: conn} do
    bytes = png()
    created = upload!(conn, bytes, "my picture.png")

    assert %{
             "id" => id,
             "filename" => "my picture.png",
             "content_type" => "image/png",
             "size" => size,
             "sha256" => sha
           } = created

    assert size == byte_size(bytes)
    assert sha == :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    download = get(conn, "/api/files/#{id}")
    assert response(download, 200) == bytes
    assert [type] = get_resp_header(download, "content-type")
    assert type =~ "image/png"
    assert [disposition] = get_resp_header(download, "content-disposition")
    assert disposition =~ "attachment"
    assert get_resp_header(download, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(download, "etag") == [~s("#{sha}")]
  end

  test "what the file is comes from its bytes, not from what the client says", %{conn: conn} do
    # a script called picture.png, claiming to be an image
    script = "<script>alert(1)</script>\0"

    bad =
      conn
      |> post("/api/files", %{"file" => upload(script, "picture.png", "image/png")})
      |> json_response(400)

    assert bad["error"] =~ "only PNG, JPEG, PDF and plain text"

    # real PDF bytes under a .png name: kept, as what they are
    created = upload!(conn, pdf(), "weird.png")
    assert created["content_type"] == "application/pdf"
  end

  test "nothing, an empty file, or too big a file", %{conn: conn} do
    assert conn |> post("/api/files", %{}) |> json_response(400)
    assert conn |> post("/api/files", %{"file" => upload("", "empty.txt")}) |> json_response(400)

    big = png() <> :binary.copy("a", 5_000_001)
    assert conn |> post("/api/files", %{"file" => upload(big, "big.png")}) |> json_response(413)
  end

  test "a file name is only for showing: no path, no control characters", %{conn: conn} do
    created = upload!(conn, png(), "../../etc/pass\x00wd.png")
    assert created["filename"] == "passwd.png"
  end

  test "a customer sees only their own files; others get a 404", %{conn: conn} do
    %{"id" => id} = upload!(conn, png())

    other = log_in(Phoenix.ConnTest.build_conn(), user_fixture())
    assert other |> get("/api/files/#{id}") |> json_response(404)
    assert other |> delete("/api/files/#{id}") |> json_response(404)
    assert %{"files" => []} = other |> get("/api/files") |> json_response(200)

    admin = log_in(Phoenix.ConnTest.build_conn(), admin_fixture())
    assert admin |> get("/api/files/#{id}") |> response(200)
  end

  test "listing is your own; deleting removes the bytes too", %{conn: conn} do
    %{"id" => a} = upload!(conn, png())
    %{"id" => b} = upload!(conn, pdf(), "x.pdf")
    assert %{"files" => files} = conn |> get("/api/files") |> json_response(200)
    assert Enum.map(files, & &1["id"]) == [b, a]

    assert conn |> delete("/api/files/#{a}") |> response(204)
    assert conn |> get("/api/files/#{a}") |> json_response(404)
    assert conn |> get("/api/files/#{b}") |> response(200)
  end

  test "a login is needed", %{conn: _} do
    anon = Phoenix.ConnTest.build_conn()
    assert anon |> post("/api/files", %{"file" => upload(png())}) |> json_response(401)
    assert anon |> get("/api/files/1") |> json_response(401)
  end

  test "an unknown or odd id is 404", %{conn: conn} do
    assert conn |> get("/api/files/999999999") |> json_response(404)
    assert conn |> get("/api/files/abc") |> json_response(404)
  end
end
