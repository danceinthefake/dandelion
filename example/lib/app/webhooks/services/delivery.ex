defmodule App.Webhooks.Services.Delivery do
  @moduledoc """
  One HTTP request to a receiver: the event as JSON, signed (`Dandelion.Webhook`).
  ≈ `http.Client.Do` in a Go delivery loop.

  It follows no redirects (a receiver that redirects to the inside of our network
  would get past the URL check), gives up after `:webhook_timeout` ms, and checks
  that the host name resolves to a public address *now* — the check made when the
  endpoint was saved is not enough, a name can change what it points at.
  """
  alias App.Webhooks.Models.Endpoint

  @type outcome :: {:ok, status :: 200..299} | {:error, term()}

  @doc "Sends `event` (a map) to `endpoint`. Non-2xx answers come back as `{:error, {:status, n}}`."
  @spec deliver(Endpoint.t(), String.t(), map()) :: outcome()
  def deliver(%Endpoint{} = endpoint, id, event) do
    body = Jason.encode!(event)

    headers = [
      {"content-type", "application/json"} | Dandelion.Webhook.headers(endpoint.secret, id, body)
    ]

    with :ok <- check_resolved(endpoint.url) do
      options =
        [
          url: endpoint.url,
          method: :post,
          body: body,
          headers: headers,
          redirect: false,
          retry: false,
          receive_timeout: timeout(),
          connect_options: [timeout: timeout()]
        ] ++ Application.get_env(:acme, :webhook_req_options, [])

      case Req.request(options) do
        {:ok, %Req.Response{status: status}} when status in 200..299 -> {:ok, status}
        {:ok, %Req.Response{status: status}} -> {:error, {:status, status}}
        {:error, exception} -> {:error, {:request, Exception.message(exception)}}
      end
    end
  end

  def timeout, do: Application.get_env(:acme, :webhook_timeout, 5_000)

  defp check_resolved(url) do
    if Application.get_env(:acme, :webhook_allow_private, false) do
      :ok
    else
      host = url |> URI.parse() |> Map.fetch!(:host) |> String.to_charlist()

      case :inet.getaddr(host, :inet) do
        {:ok, address} -> private_check(address)
        {:error, reason} -> {:error, {:dns, reason}}
      end
    end
  end

  defp private_check(address) do
    case Endpoint.check_address(address |> Tuple.to_list() |> Enum.join(".")) do
      :ok -> :ok
      {:error, _} -> {:error, :private_address}
    end
  end
end
