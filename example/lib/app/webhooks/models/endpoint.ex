defmodule App.Webhooks.Models.Endpoint do
  @moduledoc """
  A URL that wants to be told when something happens here (a webhook), with the
  secret that signs what we send it. ≈ a row of Stripe's "webhook endpoints".

  `create_changeset/2` checks the URL: it is where our servers will send requests,
  so it must not point at the inside of our own network (`localhost`, private
  addresses) unless the deployment allows it (`config :acme, :webhook_allow_private`),
  and must be `https` unless it allows `http` too (`:webhook_allow_http`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]
  schema "webhook_endpoints" do
    field :url, :string
    field :secret, :string
    field :events, {:array, :string}, default: []
    field :active, :boolean, default: true
    timestamps()
  end

  @type t :: %__MODULE__{}

  def create_changeset(attrs, valid_events) do
    %__MODULE__{}
    |> cast(attrs, [:url, :events])
    |> validate_required([:url, :events])
    |> validate_length(:url, max: 2048)
    |> validate_events_present()
    |> validate_length(:events, max: 20)
    |> validate_subset(:events, valid_events)
    |> validate_url()
    |> put_change(:secret, new_secret())
  end

  # (an empty list equals the default, so Ecto sees no change to validate)
  defp validate_events_present(changeset) do
    if get_field(changeset, :events) == [],
      do: add_error(changeset, :events, "must name at least one event"),
      else: changeset
  end

  defp new_secret,
    do: "whsec_" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

  defp validate_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      case check_url(url) do
        :ok -> []
        {:error, message} -> [url: message]
      end
    end)
  end

  @doc false
  # Also used at delivery time, on the address the name resolves to then.
  def check_url(url) do
    uri = URI.parse(url)
    http? = Application.get_env(:acme, :webhook_allow_http, false)

    if uri.scheme == "https" or (uri.scheme == "http" and http?),
      do: check_host(uri.host),
      else: {:error, if(http?, do: "must be an http or https URL", else: "must be an https URL")}
  end

  defp check_host(host) when host in [nil, ""], do: {:error, "must have a host"}

  defp check_host(host) do
    cond do
      Application.get_env(:acme, :webhook_allow_private, false) -> :ok
      host in ["localhost"] or String.ends_with?(host, ".localhost") -> private()
      match?({:ok, _}, :inet.parse_address(String.to_charlist(host))) -> check_address(host)
      true -> :ok
    end
  end

  @doc false
  def check_address(host) do
    {:ok, address} = :inet.parse_address(String.to_charlist(host))
    if private?(address), do: private(), else: :ok
  end

  defp private, do: {:error, "must not point at this machine or a private network"}

  defp private?({127, _, _, _}), do: true
  defp private?({10, _, _, _}), do: true
  defp private?({0, _, _, _}), do: true
  defp private?({169, 254, _, _}), do: true
  defp private?({172, b, _, _}) when b in 16..31, do: true
  defp private?({192, 168, _, _}), do: true
  defp private?({100, b, _, _}) when b in 64..127, do: true
  defp private?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private?({0, 0, 0, 0, 0, 0, 0, 0}), do: true

  defp private?({a, _, _, _, _, _, _, _}) when a in 0xFC00..0xFDFF or a in 0xFE80..0xFEBF,
    do: true

  defp private?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: private?({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})

  defp private?(_), do: false
end
