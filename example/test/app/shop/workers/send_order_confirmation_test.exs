defmodule App.Shop.Workers.SendOrderConfirmationTest do
  use Platform.DataCase, async: false
  use Oban.Testing, repo: Platform.Database.Repo

  import App.Shop.Fixtures
  import Swoosh.TestAssertions

  alias App.Notifications.Models.OutgoingEmail
  alias App.Shop.Workers.SendOrderConfirmation
  alias Dandelion.Resilience

  setup do
    # Resilience runs in the application; every test starts with all circuits closed
    :ets.delete_all_objects(Resilience)
    :ok
  end

  defp confirm(order), do: perform_job(SendOrderConfirmation, %{payload: %{order_id: order.id}})

  test "emails the customer, once" do
    order = order_fixture()
    assert :ok = confirm(order)

    assert_email_sent(fn email ->
      assert email.to == [{"", "sari@example.com"}]
      assert email.subject == "Your order ##{order.id}"
      assert email.text_body =~ "2 x TEA-01"
      assert email.text_body =~ "Total: 70.00"
    end)

    # a rerun of the same job (it is at-least-once) does not send it again
    assert :ok = confirm(order)
    refute_email_sent()

    assert %OutgoingEmail{status: "sent", attempts: 1, sent_at: %DateTime{}} =
             Repo.get_by!(OutgoingEmail, dedupe_key: "order_confirmation:#{order.id}")
  end

  test "cancels for an order that doesn't exist" do
    assert {:cancel, _} = perform_job(SendOrderConfirmation, %{payload: %{order_id: 0}})
    refute_email_sent()
  end

  describe "when the mail server is having a bad time" do
    defmodule DownAdapter do
      @moduledoc false
      use Swoosh.Adapter

      def deliver(_email, _config), do: {:error, :econnrefused}
    end

    defmodule RefusingAdapter do
      @moduledoc false
      use Swoosh.Adapter

      def deliver(_email, _config),
        do: {:error, {:send, {:permanent_failure, ~c"mail.example.com", ~c"550 no such user"}}}
    end

    setup do
      old = Application.get_env(:acme, Platform.Mailer)
      on_exit(fn -> Application.put_env(:acme, Platform.Mailer, old) end)
      :ok
    end

    test "a refused connection is retried, and kept for the retry" do
      Application.put_env(:acme, Platform.Mailer, adapter: DownAdapter)
      order = order_fixture()

      assert {:error, why} = confirm(order)
      assert why =~ "econnrefused"

      assert %OutgoingEmail{status: "queued", attempts: 1, last_error: error} =
               Repo.get_by!(OutgoingEmail, dedupe_key: "order_confirmation:#{order.id}")

      assert error =~ "econnrefused"

      # the server comes back: the retry sends the same row
      Application.put_env(:acme, Platform.Mailer, adapter: Swoosh.Adapters.Test)
      assert :ok = confirm(order)
      assert_email_sent(subject: "Your order ##{order.id}")

      assert %OutgoingEmail{status: "sent", attempts: 2} =
               Repo.get_by!(OutgoingEmail, dedupe_key: "order_confirmation:#{order.id}")
    end

    test "after enough failures the circuit opens: nothing is tried, the job waits" do
      Application.put_env(:acme, Platform.Mailer, adapter: DownAdapter)

      for _ <- 1..5, do: assert({:error, _} = confirm(order_fixture()))

      order = order_fixture()
      assert {:snooze, 30} = confirm(order)
      # (the message is written, but no attempt was made)
      assert %OutgoingEmail{status: "queued", attempts: 1} =
               Repo.get_by!(OutgoingEmail, dedupe_key: "order_confirmation:#{order.id}")
    end

    test "a server that says no for good ends the job, and the email is marked failed" do
      Application.put_env(:acme, Platform.Mailer, adapter: RefusingAdapter)
      order = order_fixture()

      assert {:cancel, message} = confirm(order)
      assert message =~ "refused"

      assert %OutgoingEmail{status: "failed", last_error: error} =
               Repo.get_by!(OutgoingEmail, dedupe_key: "order_confirmation:#{order.id}")

      assert error =~ "550"

      # asking again does not try again
      assert {:cancel, _} = confirm(order)
    end
  end
end
