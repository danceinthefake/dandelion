defmodule App.Files.Services.ContentType do
  @moduledoc """
  What a file is, from its bytes — never from what the client says it is (the
  `Content-Type` of a part and the file's name are both the client's to choose).
  Only these are accepted: PNG, JPEG, PDF and plain UTF-8 text.
  """

  @text_sample 8_192

  @spec detect(Path.t()) :: {:ok, String.t()} | :unknown
  def detect(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, @text_sample)) do
      {:ok, <<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>} -> {:ok, "image/png"}
      {:ok, <<0xFF, 0xD8, 0xFF, _::binary>>} -> {:ok, "image/jpeg"}
      {:ok, "%PDF-" <> _} -> {:ok, "application/pdf"}
      {:ok, bytes} when is_binary(bytes) and bytes != "" -> text(bytes)
      _ -> :unknown
    end
  end

  # valid UTF-8 and no NUL bytes; a sample that stops in the middle of a character
  # still counts (the cut is ours, not the file's)
  defp text(bytes) do
    if String.valid?(trim_partial(bytes)) and not String.contains?(bytes, <<0>>),
      do: {:ok, "text/plain"},
      else: :unknown
  end

  defp trim_partial(bytes) do
    Enum.find_value(0..3, bytes, fn cut ->
      candidate = binary_part(bytes, 0, max(byte_size(bytes) - cut, 0))
      if String.valid?(candidate), do: candidate
    end)
  end
end
