defmodule App.Accounts.Services.LoginThrottleTest do
  use Platform.DataCase, async: false

  import App.Accounts.Fixtures

  alias App.Accounts.Services.LoginThrottle

  setup do
    put_setting(:login_max_failures, 3)
    put_setting(:lockout_seconds, 600)
    {:ok, email: "t#{System.unique_integer([:positive])}@example.com"}
  end

  test "an address is typed the same however it is typed" do
    assert LoginThrottle.normalize("  Sari@Example.COM ") == "sari@example.com"
    assert LoginThrottle.normalize(nil) == "-"
    assert LoginThrottle.normalize(%{}) == "-"
    assert String.length(LoginThrottle.normalize(String.duplicate("a", 500))) == 200
  end

  test "the nth wrong password in a row locks it", %{email: email} do
    assert :ok = LoginThrottle.check(email)
    assert %{locked?: false, failures: 1} = LoginThrottle.failure(email)
    assert %{locked?: false, failures: 2} = LoginThrottle.failure(email)
    assert :ok = LoginThrottle.check(email)
    assert %{locked?: true, failures: 3} = LoginThrottle.failure(email)
    assert {:locked, seconds} = LoginThrottle.check(email)
    assert seconds in 590..600
  end

  test "more wrong guesses while locked do not extend the lock", %{email: email} do
    for _ <- 1..3, do: LoginThrottle.failure(email)
    {:locked, first} = LoginThrottle.check(email)
    assert %{locked?: false} = LoginThrottle.failure(email)
    {:locked, second} = LoginThrottle.check(email)
    assert second <= first
  end

  test "a right password forgets the failures", %{email: email} do
    LoginThrottle.failure(email)
    LoginThrottle.failure(email)
    LoginThrottle.success(email)
    assert %{failures: 1} = LoginThrottle.failure(email)
  end

  test "an address nobody has is locked the same way: a lock does not say an account exists" do
    ghost = "nobody-#{System.unique_integer([:positive])}@example.com"
    for _ <- 1..3, do: LoginThrottle.failure(ghost)
    assert {:locked, _} = LoginThrottle.check(ghost)
  end

  test "addresses are counted apart", %{email: email} do
    other = "other-#{email}"
    for _ <- 1..3, do: LoginThrottle.failure(email)
    assert {:locked, _} = LoginThrottle.check(email)
    assert :ok = LoginThrottle.check(other)
  end

  test "when the lock has run out, counting starts again", %{email: email} do
    for _ <- 1..3, do: LoginThrottle.failure(email)
    past = NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :second)
    Repo.query!("UPDATE login_throttle SET locked_until = $2 WHERE email = $1", [email, past])

    assert :ok = LoginThrottle.check(email)
    assert %{failures: 1, locked?: false} = LoginThrottle.failure(email)
  end

  test "clear unlocks", %{email: email} do
    for _ <- 1..3, do: LoginThrottle.failure(email)
    LoginThrottle.clear(email)
    assert :ok = LoginThrottle.check(email)
  end

  test "prune keeps locks and forgets old, unlocked rows", %{email: email} do
    locked = "locked-#{email}"
    for _ <- 1..3, do: LoginThrottle.failure(locked)
    LoginThrottle.failure(email)
    old = NaiveDateTime.add(NaiveDateTime.utc_now(), -2 * 86_400, :second)

    Repo.query!("UPDATE login_throttle SET updated_at = $1 WHERE email IN ($2, $3)", [
      old,
      email,
      locked
    ])

    assert LoginThrottle.prune() >= 1
    assert {:locked, _} = LoginThrottle.check(locked)
    assert %{failures: 1} = LoginThrottle.failure(email)
  end
end
