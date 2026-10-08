defmodule Dandelion.WebhookTest do
  use ExUnit.Case, async: true

  alias Dandelion.Webhook

  @secret "whsec_test"
  @body ~s({"type":"order.created","data":{"order_id":1}})

  test "a signed request verifies" do
    headers = Webhook.headers(@secret, "evt_1", @body)
    assert :ok = Webhook.verify(@secret, headers, @body)
  end

  test "the signature is the documented one: v1, base64 HMAC-SHA256 of id.timestamp.body" do
    expected =
      :crypto.mac(:hmac, :sha256, @secret, "evt_1.1700000000." <> @body) |> Base.encode64()

    assert Webhook.sign(@secret, "evt_1", 1_700_000_000, @body) == "v1," <> expected
  end

  test "another body, secret or id does not verify" do
    headers = Webhook.headers(@secret, "evt_1", @body)
    assert {:error, :bad_signature} = Webhook.verify(@secret, headers, @body <> " ")
    assert {:error, :bad_signature} = Webhook.verify("other", headers, @body)

    swapped = List.keyreplace(headers, "webhook-id", 0, {"webhook-id", "evt_2"})
    assert {:error, :bad_signature} = Webhook.verify(@secret, swapped, @body)
  end

  test "an old (or future) timestamp is refused, within a tolerance" do
    now = 1_700_000_000
    headers = Webhook.headers(@secret, "evt_1", @body, now)

    assert :ok = Webhook.verify(@secret, headers, @body, now: now + 299)
    assert {:error, :too_old} = Webhook.verify(@secret, headers, @body, now: now + 301)
    assert {:error, :too_old} = Webhook.verify(@secret, headers, @body, now: now - 301)
    assert :ok = Webhook.verify(@secret, headers, @body, now: now + 3_000, tolerance: 4_000)
  end

  test "headers may be a map with any case; missing ones are named" do
    headers =
      Webhook.headers(@secret, "evt_1", @body) |> Map.new(fn {k, v} -> {String.upcase(k), v} end)

    assert :ok = Webhook.verify(@secret, headers, @body)
    assert {:error, :missing_headers} = Webhook.verify(@secret, %{}, @body)

    broken = %{"webhook-id" => "x", "webhook-timestamp" => "soon", "webhook-signature" => "v1,x"}
    assert {:error, :missing_headers} = Webhook.verify(@secret, broken, @body)
  end

  test "several signatures (a secret being rotated): any match is enough" do
    now = System.os_time(:second)
    good = Webhook.sign(@secret, "evt_1", now, @body)
    stale = Webhook.sign("old-secret", "evt_1", now, @body)

    headers = %{
      "webhook-id" => "evt_1",
      "webhook-timestamp" => Integer.to_string(now),
      "webhook-signature" => stale <> " " <> good
    }

    assert :ok = Webhook.verify(@secret, headers, @body)
  end
end
