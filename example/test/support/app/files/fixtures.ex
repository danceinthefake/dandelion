defmodule App.Files.Fixtures do
  @moduledoc "Test helpers for uploads."

  alias App.Files.Services.FileService

  @png <<0x89, "PNG\r\n", 0x1A, "\n", 0, 0, 0, 13, "IHDR", 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0,
         31, 21, 196, 137>>

  def png, do: @png <> :crypto.strong_rand_bytes(32)
  def pdf, do: "%PDF-1.4\n" <> :crypto.strong_rand_bytes(32)
  def jpeg, do: <<0xFF, 0xD8, 0xFF, 0xE0>> <> :crypto.strong_rand_bytes(32)

  @doc "A `Plug.Upload` over a temporary file with `content` — what a multipart request becomes."
  def upload(content, filename \\ "file.bin", content_type \\ "application/octet-stream") do
    path = Path.join(System.tmp_dir!(), "upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  @doc "Empties the uploads directory, now and after the test."
  def clean_uploads do
    root = FileService.root()
    File.rm_rf!(root)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)
  end
end
