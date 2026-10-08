defmodule Dandelion.StorageTest do
  use ExUnit.Case, async: true

  alias Dandelion.Storage.Local

  @moduletag :tmp_dir

  defp source(dir, content) do
    path = Path.join(dir, "upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  test "put stores the bytes under a random key and reports size and sha256", %{tmp_dir: dir} do
    root = Path.join(dir, "store")
    src = source(dir, "hello world")

    assert {:ok, %{key: key, size: 11, sha256: sha}} = Local.put(root, src)
    assert key =~ ~r/\A[0-9a-f]{32}\z/
    assert sha == :crypto.hash(:sha256, "hello world") |> Base.encode16(case: :lower)

    assert {:ok, path} = Local.path(root, key)
    assert File.read!(path) == "hello world"
    assert File.exists?(src), "the source is left alone"
  end

  test "the same content stored twice is two files with two keys", %{tmp_dir: dir} do
    root = Path.join(dir, "store")
    src = source(dir, "same")
    {:ok, a} = Local.put(root, src)
    {:ok, b} = Local.put(root, src)
    refute a.key == b.key
    assert a.sha256 == b.sha256
  end

  test "an empty file and a big one", %{tmp_dir: dir} do
    root = Path.join(dir, "store")
    assert {:ok, %{size: 0}} = Local.put(root, source(dir, ""))
    big = :crypto.strong_rand_bytes(1_000_003)
    assert {:ok, %{size: 1_000_003, sha256: sha, key: key}} = Local.put(root, source(dir, big))
    assert sha == :crypto.hash(:sha256, big) |> Base.encode16(case: :lower)
    assert File.read!(elem(Local.path(root, key), 1)) == big
  end

  test "a missing source is an error and leaves nothing behind", %{tmp_dir: dir} do
    root = Path.join(dir, "store")
    assert {:error, :enoent} = Local.put(root, Path.join(dir, "nope"))
    assert Local.keys(root) == []
    assert File.ls!(Path.join(root, "tmp")) == []
  end

  test "no key can reach outside the directory", %{tmp_dir: dir} do
    root = Path.join(dir, "store")
    File.write!(Path.join(dir, "secret"), "x")
    {:ok, _} = Local.put(root, source(dir, "a"))

    for bad <- [
          "../secret",
          "..",
          "/etc/passwd",
          "ab/../../secret",
          "",
          nil,
          5,
          String.duplicate("a", 31),
          String.duplicate("A", 32)
        ] do
      assert {:error, :not_found} = Local.path(root, bad), inspect(bad)
      assert :ok = Local.delete(root, bad)
    end

    assert File.exists?(Path.join(dir, "secret"))
  end

  test "delete removes the file, and deleting twice is fine", %{tmp_dir: dir} do
    root = Path.join(dir, "store")
    {:ok, %{key: key}} = Local.put(root, source(dir, "bye"))
    assert :ok = Local.delete(root, key)
    assert {:error, :not_found} = Local.path(root, key)
    assert :ok = Local.delete(root, key)
  end

  test "keys lists what is stored", %{tmp_dir: dir} do
    root = Path.join(dir, "store")
    assert Local.keys(root) == []
    {:ok, a} = Local.put(root, source(dir, "a"))
    {:ok, b} = Local.put(root, source(dir, "b"))
    assert Enum.sort(Local.keys(root)) == Enum.sort([a.key, b.key])
  end
end
