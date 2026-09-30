defmodule Platform.Web.PageHandler do
  @moduledoc """
  Serves the Vue app's shell (`priv/static/app/index.html`, built from
  `assets/`). The shell holds no data; everything comes from `/api` and the
  `/socket` WebSocket.
  """
  use Platform.Web, :handler

  def index(conn, _params) do
    path = Application.app_dir(:acme, "priv/static/app/index.html")

    if File.exists?(path) do
      conn |> put_resp_content_type("text/html") |> send_file(200, path)
    else
      send_resp(conn, 503, "The UI isn't built yet: cd assets && npm install && npm run build")
    end
  end
end
