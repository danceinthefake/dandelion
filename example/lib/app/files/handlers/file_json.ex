defmodule App.Files.Handlers.FileJSON do
  @moduledoc "The JSON shape of a stored file."

  def file(f) do
    %{
      id: f.id,
      filename: f.filename,
      content_type: f.content_type,
      size: f.size,
      sha256: f.sha256,
      created_at: f.inserted_at
    }
  end
end
