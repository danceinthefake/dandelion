defmodule App.Files.Services.FileServiceTest do
  use Platform.DataCase, async: false

  import App.Accounts.Fixtures
  import App.Files.Fixtures

  alias App.Files.Services.FileService
  alias Dandelion.Storage.Local

  setup do
    clean_uploads()
    user = user_fixture()
    {:ok, viewer: %{id: user.id, role: user.role}}
  end

  test "if the row can't be saved, the bytes are not left behind" do
    nobody = %{id: 0, role: "customer"}
    assert {:error, %Ecto.Changeset{}} = FileService.create(upload(png()), nobody)
    assert Local.keys(FileService.root()) == []
  end

  test "a file that is not a plain upload is refused", %{viewer: viewer} do
    assert {:error, {:invalid, _}} = FileService.create("not an upload", viewer)
    assert {:error, {:invalid, _}} = FileService.create(nil, viewer)
  end

  test "the stored row and the bytes agree", %{viewer: viewer} do
    bytes = png()
    assert {:ok, file} = FileService.create(upload(bytes, "a.png"), viewer)
    assert {:ok, ^file, {:file, path}} = FileService.get(file.id, viewer)
    assert File.read!(path) == bytes
    assert file.sha256 == :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  end

  test "a row whose bytes are gone is a not found, not a crash", %{viewer: viewer} do
    {:ok, file} = FileService.create(upload(png()), viewer)
    Local.delete(FileService.root(), file.storage_key)
    assert {:error, :not_found} = FileService.get(file.id, viewer)
  end

  test "a file name is made harmless", %{viewer: viewer} do
    for {given, shown} <- [
          {"a/b/c.png", "c.png"},
          {"..\\..\\windows\\x.png", "x.png"},
          {"line\nbreak.png", "linebreak.png"},
          {"", "file"},
          {String.duplicate("n", 400) <> ".png",
           String.slice(String.duplicate("n", 400) <> ".png", 0, 255)}
        ] do
      assert {:ok, %{filename: ^shown}} = FileService.create(upload(png(), given), viewer)
    end
  end
end
