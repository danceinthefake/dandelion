defmodule Dandelion.Webhook do
  @moduledoc """
  Signing what you send to another service's URL, and checking what you receive.
  ≈ Stripe's `Stripe-Signature`, GitHub's `X-Hub-Signature-256` — the same idea,
  following the [Standard Webhooks](https://www.standardwebhooks.com) headers.

  A receiver must be able to tell that a request came from you, was not changed,
  and is not an old one replayed. So each delivery carries three headers:

    * `webhook-id` — one id for the event, **the same on every retry**: a receiver
      that sees an id twice has seen this event already (delivery is at least once);
    * `webhook-timestamp` — seconds since the epoch, when it was sent;
    * `webhook-signature` — `v1,` and the base64 HMAC-SHA256, with the endpoint's
      secret, of `"<id>.<timestamp>.<body>"`.

  Sending (`headers/4`):

      body = Jason.encode!(event)
      headers = Dandelion.Webhook.headers(secret, "evt_123", body)

  Receiving (`verify/4`), on the exact bytes of the body, before parsing it:

      :ok = Dandelion.Webhook.verify(secret, headers, raw_body)

  A signature older or newer than `:tolerance` seconds (default 300) is refused, so
  a captured request can't be replayed later. The comparison takes the same time
  whatever the input. This module sends nothing: delivery, retries and the circuit
  are your worker's job (`Dandelion.Resilience`).
  """

  @default_tolerance 300

  @doc """
  The `webhook-signature` value for `body` sent as event `id` at `timestamp`
  (seconds): `"v1,<base64 hmac>"`.
  """
  @spec sign(binary(), String.t(), integer(), binary()) :: String.t()
  def sign(secret, id, timestamp, body) do
    mac = :crypto.mac(:hmac, :sha256, secret, "#{id}.#{timestamp}.#{body}")
    "v1," <> Base.encode64(mac)
  end

  @doc "The three headers to send with `body`, as a list of `{name, value}`."
  @spec headers(binary(), String.t(), binary(), integer()) :: [{String.t(), String.t()}]
  def headers(secret, id, body, now \\ System.os_time(:second)) do
    [
      {"webhook-id", id},
      {"webhook-timestamp", Integer.to_string(now)},
      {"webhook-signature", sign(secret, id, now, body)}
    ]
  end

  @doc """
  Checks the headers of a received request against its raw `body`. `headers` is a
  list of `{name, value}` or a map, names in any case. Returns `:ok`,
  `{:error, :missing_headers}`, `{:error, :too_old}` (or too far in the future) or
  `{:error, :bad_signature}`.

  A signature header may hold several space-separated `v1,…` values (a secret that
  is being rotated); any one that matches is enough.
  """
  @spec verify(binary(), Enumerable.t(), binary(), keyword()) :: :ok | {:error, atom()}
  def verify(secret, headers, body, opts \\ []) do
    headers = for {k, v} <- headers, into: %{}, do: {String.downcase(to_string(k)), v}
    now = Keyword.get(opts, :now, System.os_time(:second))
    tolerance = Keyword.get(opts, :tolerance, @default_tolerance)

    with %{"webhook-id" => id, "webhook-timestamp" => ts, "webhook-signature" => sigs} <- headers,
         {timestamp, ""} <- Integer.parse(ts) do
      cond do
        abs(now - timestamp) > tolerance -> {:error, :too_old}
        matches?(sign(secret, id, timestamp, body), sigs) -> :ok
        true -> {:error, :bad_signature}
      end
    else
      _ -> {:error, :missing_headers}
    end
  end

  defp matches?(expected, signatures) do
    signatures
    |> String.split(" ", trim: true)
    |> Enum.reduce(false, fn candidate, found ->
      equal?(expected, candidate) or found
    end)
  end

  defp equal?(a, b) when byte_size(a) == byte_size(b), do: :crypto.hash_equals(a, b)
  defp equal?(_a, _b), do: false
end
