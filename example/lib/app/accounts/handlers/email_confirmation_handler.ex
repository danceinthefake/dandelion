defmodule App.Accounts.Handlers.EmailConfirmationHandler do
  @moduledoc "Confirming an email address with a link, and asking for the link again. ≈ `http/confirm.go`."
  use Platform.Web, :handler

  alias App.Accounts.Handlers.UserJSON
  alias App.Accounts.Services.AccountService

  action_fallback Platform.Web.FallbackHandler

  # POST /api/email/confirm   {"token": "…"}
  def confirm(conn, %{"token" => token}) do
    with {:ok, user} <- AccountService.confirm_email(token), do: json(conn, UserJSON.user(user))
  end

  def confirm(_conn, _params), do: {:error, {:invalid, "send a token"}}

  # POST /api/email/resend   (needs a login)
  def resend(conn, _params) do
    with :ok <- AccountService.resend_confirmation(conn.assigns.current_user) do
      conn |> put_status(:accepted) |> json(%{status: "an email is on its way"})
    end
  end
end
