defmodule App.Notifications.Services.EmailService do
  @moduledoc """
  Sending an email once, whatever goes wrong on the way. ≈ `service/mail.go`.

  `send_once/5` is what a job calls (at least once, like every job):

    1. the message is written to `outgoing_emails` under its `dedupe_key` (or found, if an
       earlier run wrote it) — a rerun of the same job finds the row and **does not send again**
       once it is `sent`;
    2. it is sent through `Dandelion.Resilience`: a timeout, and a circuit per mail server, so a
       mail server that is down costs us a timestamp, not a worker stuck on a connection;
    3. the row is marked `sent` — or `failed`, when the server says no for good (a bad address).

  The answer is what the caller should do:

      :ok                          sent, now or before
      {:error, :circuit_open}      the server is down and we know it: try again later, don't count it
      {:error, {:temporary, why}}  try again (the server was busy, a timeout, a dropped connection)
      {:error, {:permanent, why}}  don't: the server refused (550 no such user, …)

  **At least once, not exactly once.** If the server accepts a message and we crash before
  marking the row, the retry sends it again. That window is one database write wide, and it is
  the same for every system that sends mail; the dedupe key removes every other duplicate.
  """
  import Swoosh.Email

  alias App.Notifications.Models.OutgoingEmail
  alias Dandelion.Resilience
  alias Platform.Database.Repos.EmailRepo
  alias Platform.Mailer

  @type result :: :ok | {:error, :circuit_open | {:temporary, term()} | {:permanent, term()}}

  @spec send_once(String.t(), String.t(), String.t(), String.t(), String.t()) :: result()
  def send_once(dedupe_key, kind, to, subject, body) do
    email =
      EmailRepo.get_or_create(%{
        dedupe_key: dedupe_key,
        kind: kind,
        to_address: to,
        subject: subject,
        body: body
      })

    case email.status do
      "sent" -> :ok
      "failed" -> {:error, {:permanent, email.last_error}}
      "queued" -> deliver(email)
    end
  end

  defp deliver(%OutgoingEmail{} = email) do
    EmailRepo.attempt(email)

    message =
      new()
      |> to(email.to_address)
      |> from(Application.fetch_env!(:acme, :mail_from))
      |> subject(email.subject)
      |> text_body(email.body)

    host = Application.get_env(:acme, :mail_host, "log")

    case Resilience.call({:smtp, host}, fn -> Mailer.deliver(message) end,
           timeout: 20_000,
           failure_threshold: 5,
           reset_after: reset_after()
         ) do
      {:ok, _} ->
        EmailRepo.mark_sent(email)

      {:error, :circuit_open} ->
        {:error, :circuit_open}

      {:error, reason} ->
        failed(email, reason)
    end
  end

  defp failed(email, reason) do
    text = reason |> inspect() |> String.slice(0, 500)

    if permanent?(reason) do
      EmailRepo.mark_failed(email, text)
      {:error, {:permanent, text}}
    else
      EmailRepo.record_error(email, text)
      {:error, {:temporary, text}}
    end
  end

  # gen_smtp reports a refusal as {:permanent_failure, host, message} somewhere inside the
  # error (a 5xx answer); everything else — timeouts, refused connections, 4xx — can pass.
  defp permanent?(:permanent_failure), do: true
  defp permanent?(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> permanent?()
  defp permanent?(list) when is_list(list), do: Enum.any?(list, &permanent?/1)
  defp permanent?(_other), do: false

  defp reset_after, do: Application.get_env(:acme, :mail_circuit_reset, 30_000)
end
