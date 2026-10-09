defmodule App.Accounts.Workers.SendAccountEmail do
  @moduledoc """
  Sends a one-time link: `"reset"` (a password reset) or `"confirm"` (an address confirmation).
  ≈ a job that mails a "magic link".

  The link's secret is made **here**, when the email is written, and goes only into the email — not
  into the job's arguments (those are rows that stay a week). The email is written down under the
  job's id before it is sent, so a retry sends the same message with the same link, not a new one;
  and once the mail server has it, the body is blanked (`EmailService`).

  The links open pages of the console (`assets/src/pages/ResetPasswordPage.vue`,
  `ConfirmEmailPage.vue`); a project without the console still has the code in the email, to use with
  the API.

  Asked for twice within a minute for the same user, the second asking is the same job.
  """
  use Oban.Worker,
    queue: :mail,
    max_attempts: 10,
    unique: [
      period: 60,
      keys: [:user_id, :kind],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias App.Accounts.Services.TokenService
  alias App.Notifications.Services.EmailService
  alias Platform.Database.Repos.UserRepo
  alias Platform.Web.Endpoint

  @impl Oban.Worker
  def perform(%Oban.Job{id: id, args: %{"user_id" => user_id, "kind" => kind}})
      when kind in ["reset", "confirm"] do
    case UserRepo.get(user_id) do
      nil ->
        {:cancel, "user #{user_id} is gone"}

      user ->
        {email_kind, subject, path, text} = template(kind)

        "account_email:#{id}"
        |> EmailService.send_once_lazy(email_kind, user.email, subject, fn ->
          secret = TokenService.issue(user.id, kind)
          body(text, base_url() <> path <> secret, secret)
        end)
        |> EmailService.oban_result()
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    base = Application.get_env(:acme, :mail_backoff_seconds, 30)
    round(min(base * Integer.pow(2, attempt - 1), 3_600) * (0.8 + :rand.uniform() * 0.4))
  end

  # Where the links point: the console, with the secret after the `#` — a browser never sends that
  # part to a server, so it is in no access log. `PUBLIC_URL` is the address people reach the service
  # at (the local cluster is http://localhost:8080); without it, the endpoint's own URL.
  defp base_url, do: Application.get_env(:acme, :public_url) || Endpoint.url()

  defp template("reset"),
    do:
      {"password_reset", "Reset your password", "/#/reset-password?token=",
       "Somebody asked to reset the password of this account. If it was you, use this link (it works once, for an hour):"}

  defp template("confirm"),
    do:
      {"email_confirmation", "Confirm your email address", "/#/confirm-email?token=",
       "Please confirm that this is your email address, with this link (it works once, for three days):"}

  defp body(text, link, secret) do
    """
    Hello,

    #{text}

      #{link}

    Or, to use the API: the code is  #{secret}

    If you did not ask for this, ignore this email: nothing changes until the link is used.
    """
  end
end
