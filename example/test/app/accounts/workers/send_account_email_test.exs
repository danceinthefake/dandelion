defmodule App.Accounts.Workers.SendAccountEmailTest do
  use Platform.DataCase, async: false
  use Oban.Testing, repo: Platform.Database.Repo

  import App.Accounts.Fixtures
  import Swoosh.TestAssertions

  alias App.Accounts.Services.TokenService
  alias App.Accounts.Workers.SendAccountEmail
  alias App.Notifications.Models.OutgoingEmail
  alias Dandelion.Resilience

  setup do
    :ets.delete_all_objects(Resilience)
    {:ok, user: user_fixture()}
  end

  defp run(user, kind), do: perform_job(SendAccountEmail, %{"user_id" => user.id, "kind" => kind})

  defmodule DownAdapter do
    @moduledoc false
    use Swoosh.Adapter
    def deliver(_email, _config), do: {:error, :econnrefused}
  end

  test "a reset email has the link and the code, and a working secret", %{user: user} do
    assert :ok = run(user, "reset")

    assert_email_sent(fn email ->
      assert email.to == [{"", user.email}]
      assert email.subject == "Reset your password"
      assert email.text_body =~ "/reset-password?token="
      assert [_, secret] = Regex.run(~r/the code is\s+(\S+)/, email.text_body)
      assert {:ok, user_id} = TokenService.consume(secret, "reset")
      assert user_id == user.id
    end)
  end

  test "a confirmation email is for confirming", %{user: user} do
    assert :ok = run(user, "confirm")
    assert_email_sent(subject: "Confirm your email address")
  end

  test "once the mail server has it, the body that held the link is blanked", %{user: user} do
    run(user, "reset")

    assert [%OutgoingEmail{status: "sent", body: body, kind: "password_reset"}] =
             Repo.all(from e in OutgoingEmail, where: e.to_address == ^user.email)

    refute body =~ "token="
    assert body =~ "removed"
  end

  test "the link is not in the job's arguments: they are kept for a week", %{user: user} do
    Oban.insert!(SendAccountEmail.new(%{"user_id" => user.id, "kind" => "reset"}))
    [job] = all_enqueued(worker: SendAccountEmail)
    assert job.args == %{"user_id" => user.id, "kind" => "reset"}
  end

  describe "when the mail server is down" do
    setup do
      old = Application.get_env(:acme, Platform.Mailer)
      on_exit(fn -> Application.put_env(:acme, Platform.Mailer, old) end)
      Application.put_env(:acme, Platform.Mailer, adapter: DownAdapter)
    end

    test "the job is retried, and the retry sends the same email with the same link", %{
      user: user
    } do
      Oban.insert!(SendAccountEmail.new(%{"user_id" => user.id, "kind" => "reset"}))
      [job] = all_enqueued(worker: SendAccountEmail)

      assert {:error, _} = SendAccountEmail.perform(job)
      [first] = Repo.all(from e in OutgoingEmail, where: e.to_address == ^user.email)
      assert first.status == "queued"
      [secret] = Regex.run(~r/token=(\S+)/, first.body, capture: :all_but_first)

      Application.put_env(:acme, Platform.Mailer, adapter: Swoosh.Adapters.Test)
      assert :ok = SendAccountEmail.perform(job)

      assert_email_sent(fn email -> assert email.text_body =~ secret end)
      # one email, one link: the retry did not make a second
      assert [_] = Repo.all(from e in OutgoingEmail, where: e.to_address == ^user.email)
      assert {:ok, _} = TokenService.consume(secret, "reset")
    end
  end

  test "a user who is gone gets nothing" do
    assert {:cancel, _} = perform_job(SendAccountEmail, %{"user_id" => 0, "kind" => "reset"})
    refute_email_sent()
  end

  test "the same kind for the same user at once is one job", %{user: user} do
    args = %{"user_id" => user.id, "kind" => "reset"}
    {:ok, first} = Oban.insert(SendAccountEmail.new(args))
    {:ok, second} = Oban.insert(SendAccountEmail.new(args))
    assert first.id == second.id
    assert {:ok, other} = Oban.insert(SendAccountEmail.new(%{args | "kind" => "confirm"}))
    refute other.id == first.id
  end
end
