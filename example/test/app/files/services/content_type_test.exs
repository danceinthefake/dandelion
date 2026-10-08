defmodule App.Files.Services.ContentTypeTest do
  use ExUnit.Case, async: true

  import App.Files.Fixtures

  alias App.Files.Services.ContentType

  defp detect(content), do: content |> upload() |> Map.fetch!(:path) |> ContentType.detect()

  test "PNG, JPEG, PDF and text are told apart by their bytes" do
    assert {:ok, "image/png"} = detect(png())
    assert {:ok, "image/jpeg"} = detect(jpeg())
    assert {:ok, "application/pdf"} = detect(pdf())
    assert {:ok, "text/plain"} = detect("just some text\nand more, with accents: café\n")
  end

  test "everything else is refused: executables, scripts with NULs, archives, empty files" do
    assert :unknown = detect(<<0x7F, "ELF", 0, 1, 2>>)
    assert :unknown = detect("MZ" <> <<0, 0>>)
    assert :unknown = detect("PK" <> <<3, 4, 0, 0>>)
    assert :unknown = detect("has a\0NUL byte")
    assert :unknown = detect(<<0xC3, 0x28, 0xA0, 0xA1>>)
    assert :unknown = detect("")
  end

  test "text cut in the middle of a character by the sample is still text" do
    text = String.duplicate("é", 5_000)
    assert {:ok, "text/plain"} = detect(text)
  end

  test "a missing file is unknown" do
    assert :unknown = ContentType.detect("/nonexistent/file")
  end
end
