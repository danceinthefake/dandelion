defmodule Platform.Mailer do
  @moduledoc """
  Sending email. ≈ the SMTP client in a Go service ([Swoosh](https://hexdocs.pm/swoosh)
  is the library). Which server is in the environment (`config/runtime.exs`):

    * `SMTP_HOST` set — mail goes there (`SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`,
      `SMTP_TLS`: `always`, `if_available` (default) or `never`);
    * not set — nothing is sent; each message is written to the log, where a real one
      would go (so a new project works without a mail server).

  Don't call this directly from a request or a job: use
  `App.Notifications.Services.EmailService`, which records the message, sends it once, and
  leaves a dead mail server to the circuit and the retries.
  """
  use Swoosh.Mailer, otp_app: :acme
end
