defmodule App.Webhooks.Models.EndpointTest do
  use ExUnit.Case, async: false

  alias App.Webhooks.Models.Endpoint

  setup do
    old = Application.get_env(:acme, :webhook_allow_private)
    Application.put_env(:acme, :webhook_allow_private, false)
    on_exit(fn -> Application.put_env(:acme, :webhook_allow_private, old) end)
  end

  defp url_error(url) do
    changeset =
      Endpoint.create_changeset(%{"url" => url, "events" => ["order.created"]}, ["order.created"])

    changeset.errors[:url]
  end

  test "a public https URL is fine" do
    assert is_nil(url_error("https://hooks.example.com/in"))
    assert is_nil(url_error("https://93.184.216.34/in"))
  end

  test "http is refused unless the deployment allows it" do
    assert {"must be an https URL", _} = url_error("http://hooks.example.com/in")
    Application.put_env(:acme, :webhook_allow_http, true)
    on_exit(fn -> Application.put_env(:acme, :webhook_allow_http, false) end)
    assert is_nil(url_error("http://hooks.example.com/in"))
    assert {"must be an http or https URL", _} = url_error("ftp://hooks.example.com/in")
  end

  test "this machine and private networks are refused" do
    for url <- [
          "https://localhost/in",
          "https://app.localhost/in",
          "https://127.0.0.1/in",
          "https://10.1.2.3/in",
          "https://172.16.0.1/in",
          "https://172.31.255.255/in",
          "https://192.168.1.1/in",
          "https://169.254.169.254/latest/meta-data",
          "https://100.64.0.1/in",
          "https://0.0.0.0/in",
          "https://[::1]/in",
          "https://[fd00::1]/in",
          "https://[::ffff:10.0.0.1]/in"
        ] do
      assert {"must not point at this machine or a private network", _} = url_error(url), url
    end

    assert is_nil(url_error("https://172.32.0.1/in"))
  end

  test "private addresses are allowed when the deployment says so" do
    Application.put_env(:acme, :webhook_allow_private, true)
    assert is_nil(url_error("https://127.0.0.1/in"))
  end

  test "no host, or not a URL" do
    assert {"must be an https URL", _} = url_error("hooks.example.com")
    assert {"must have a host", _} = url_error("https:///in")
  end

  test "events must be known, and at least one" do
    assert %{events: [_]} =
             errors(%{"url" => "https://a.example.com", "events" => ["order.exploded"]})

    assert %{events: [_]} = errors(%{"url" => "https://a.example.com", "events" => []})
  end

  defp errors(attrs) do
    attrs
    |> Endpoint.create_changeset(["order.created"])
    |> Ecto.Changeset.traverse_errors(fn {m, _} -> m end)
  end

  test "each endpoint gets its own long random secret" do
    a =
      Endpoint.create_changeset(
        %{"url" => "https://a.example.com", "events" => ["order.created"]},
        ["order.created"]
      )

    b =
      Endpoint.create_changeset(
        %{"url" => "https://a.example.com", "events" => ["order.created"]},
        ["order.created"]
      )

    secret = Ecto.Changeset.get_change(a, :secret)
    assert "whsec_" <> rest = secret
    assert byte_size(rest) >= 32
    refute secret == Ecto.Changeset.get_change(b, :secret)
  end
end
