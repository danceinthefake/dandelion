defmodule App.Accounts.Fixtures do
  @moduledoc "Test helpers for users and logging in."
  import Plug.Conn

  alias App.Accounts.Handlers.Token
  alias App.Accounts.Services.UserService
  alias App.Accounts.Workers.SendAccountEmail

  @password "correct horse battery"

  def password, do: @password

  @doc "A user in the database (a customer unless `role` says otherwise)."
  def user_fixture(attrs \\ %{}, role \\ "customer") do
    email = "user-#{System.unique_integer([:positive])}@example.com"
    params = Map.merge(%{"email" => email, "password" => @password}, attrs)
    {:ok, user} = UserService.register(params, role)
    user
  end

  def admin_fixture(attrs \\ %{}), do: user_fixture(attrs, "admin")

  @doc "The conn, sending this user's token."
  def log_in(conn, user), do: put_req_header(conn, "authorization", "Bearer " <> Token.sign(user))

  @doc """
  Runs the email job a request queued (`kind`: "reset" or "confirm") for this user, and returns
  the secret that went into the email: what a person would find in their inbox.
  """
  def email_secret(user, kind) do
    job =
      Oban.Testing.all_enqueued(repo: Platform.Database.Repo, worker: SendAccountEmail)
      |> Enum.find(&(&1.args == %{"user_id" => user.id, "kind" => kind}))

    :ok = SendAccountEmail.perform(job)

    receive do
      {:email, %{to: [{_, address}]} = email} when address == user.email ->
        [_, secret] = Regex.run(~r/the code is\s+(\S+)/, email.text_body)
        secret
    after
      500 -> raise "no email was sent to #{user.email}"
    end
  end

  @doc "Puts a setting of the accounts domain for the length of a test."
  def put_setting(key, value) do
    old = Application.fetch_env!(:acme, App.Accounts)
    Application.put_env(:acme, App.Accounts, Keyword.put(old, key, value))
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:acme, App.Accounts, old) end)
  end
end
