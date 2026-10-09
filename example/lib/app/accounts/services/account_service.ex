defmodule App.Accounts.Services.AccountService do
  @moduledoc """
  Keeping an account yours: a forgotten password, an address that is real. ≈ `service/accounts.go`.

  **A password reset** is an email with a one-time link (`TokenService`, one hour). Asking for one
  never says whether the address has an account — the answer is the same either way — and the
  email is sent from a job (`App.Accounts.Workers.SendAccountEmail`), so a mail server that is
  down delays it and does not fail the request. Using the link sets the new password, forgets the
  failed logins that locked the address, and — because every login token carries a fingerprint of
  the password (`App.Accounts.Handlers.Token`) — **ends every session the old password had**. A
  reset also confirms the address: only its owner could have read the email.

  **An address confirmation** is the same kind of link, sent at registration (and again on
  request). Whether an order needs it is a setting (`require_confirmed_email`), off by default.

  Everything that changes an account is recorded (`AuditService`), never with a link in it.
  """
  alias App.Accounts.Models.User
  alias App.Accounts.Services.{LoginThrottle, Password, TokenService}
  alias App.Accounts.Settings
  alias App.Accounts.Workers.SendAccountEmail
  alias App.Audit.Services.AuditService
  alias Platform.Database.Repo
  alias Platform.Database.Repos.UserRepo

  @doc "Starts a password reset for the address typed. Always `:ok`: it does not say whether there is an account."
  @spec request_password_reset(term()) :: :ok
  def request_password_reset(typed) do
    email = LoginThrottle.normalize(typed)
    user = UserRepo.get_by_email(email)

    if user && not TokenService.issued_within?(user.id, "reset", Settings.resend_gap_seconds()),
      do: enqueue(user, "reset")

    AuditService.record("anonymous", "password.reset_requested", "email:#{email}", %{
      known: user != nil
    })

    :ok
  end

  @doc """
  Sets a new password with the link's secret. A password that is too short is refused **without**
  using the link up. `{:error, {:invalid, …}}` for every way a link can be wrong.
  """
  @spec reset_password(term(), term()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | {:invalid, String.t()}}
  def reset_password(secret, password) do
    changeset = User.password_changeset(%User{}, %{"password" => password})

    if changeset.valid? do
      # the slow part, before the transaction: one that waits a quarter of a second for a hash holds a connection
      secret |> use_reset_link(Password.hash(changeset.changes.password)) |> invalid_link_error()
    else
      {:error, %{changeset | action: :update}}
    end
  end

  defp use_reset_link(secret, hash) do
    Repo.transact(fn ->
      with {:ok, user_id} <- TokenService.consume(secret, "reset"),
           %User{} = user <- UserRepo.get(user_id) || {:error, :invalid},
           {:ok, user} <- UserRepo.update_password(user, hash) do
        LoginThrottle.clear(user.email)
        AuditService.record("user:#{user.id}", "password.reset", "user:#{user.id}")
        {:ok, user}
      end
    end)
  end

  defp invalid_link_error({:error, :invalid}), do: {:error, invalid_link()}
  defp invalid_link_error(other), do: other

  @doc "Sends the address confirmation (at registration). Nothing for an address already confirmed."
  @spec send_confirmation(User.t()) :: :ok
  def send_confirmation(%User{} = user) do
    unless User.confirmed?(user), do: enqueue(user, "confirm")
    :ok
  end

  @doc "A logged-in user asks for the confirmation again."
  @spec resend_confirmation(User.t()) :: :ok | {:error, {:conflict, String.t()}}
  def resend_confirmation(%User{} = user) do
    cond do
      User.confirmed?(user) ->
        {:error, {:conflict, "this address is already confirmed"}}

      TokenService.issued_within?(user.id, "confirm", Settings.resend_gap_seconds()) ->
        :ok

      true ->
        enqueue(user, "confirm")
        :ok
    end
  end

  @doc "Confirms the address with the link's secret."
  @spec confirm_email(term()) :: {:ok, User.t()} | {:error, {:invalid, String.t()}}
  def confirm_email(secret) do
    result =
      Repo.transact(fn ->
        with {:ok, user_id} <- TokenService.consume(secret, "confirm"),
             %User{} = user <- UserRepo.get(user_id) || {:error, :invalid},
             {:ok, user} <- UserRepo.confirm_email(user) do
          AuditService.record("user:#{user.id}", "email.confirmed", "user:#{user.id}")
          {:ok, user}
        end
      end)

    invalid_link_error(result)
  end

  @doc "May this user make an order? (Only a setting can say no: `require_confirmed_email`.)"
  @spec may_order?(User.t()) :: boolean()
  def may_order?(%User{} = user),
    do: not Settings.require_confirmed_email?() or User.confirmed?(user)

  defp enqueue(%User{id: id}, kind),
    do: Oban.insert!(SendAccountEmail.new(%{"user_id" => id, "kind" => kind}))

  defp invalid_link,
    do: {:invalid, "this link is not valid (any more): it may have been used, or have expired"}
end
