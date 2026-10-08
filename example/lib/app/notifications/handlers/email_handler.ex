defmodule App.Notifications.Handlers.EmailHandler do
  @moduledoc "What the app has sent, and what failed. Admins only (the router's `:admin` pipeline)."
  use Platform.Web, :handler

  alias Platform.Database.Repos.EmailRepo

  @statuses ~w(queued sent failed)

  action_fallback Platform.Web.FallbackHandler

  # GET /api/emails?status=failed&before=100&limit=50
  def index(conn, params) do
    with {:ok, status} <- status(params["status"]),
         {:ok, before} <- positive(params["before"], nil),
         {:ok, limit} <- positive(params["limit"], 50) do
      emails = EmailRepo.list(status, before, min(limit, 200))
      json(conn, %{emails: Enum.map(emails, &email/1)})
    end
  end

  defp email(e) do
    %{
      id: e.id,
      kind: e.kind,
      to: e.to_address,
      subject: e.subject,
      status: e.status,
      attempts: e.attempts,
      last_error: e.last_error,
      sent_at: e.sent_at
    }
  end

  defp status(nil), do: {:ok, nil}
  defp status(s) when s in @statuses, do: {:ok, s}
  defp status(_), do: {:error, {:invalid, "status must be one of: #{Enum.join(@statuses, ", ")}"}}

  defp positive(nil, default), do: {:ok, default}

  defp positive(value, _default) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, {:invalid, "before and limit must be positive whole numbers"}}
    end
  end
end
