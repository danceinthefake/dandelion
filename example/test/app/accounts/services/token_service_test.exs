defmodule App.Accounts.Services.TokenServiceTest do
  use Platform.DataCase, async: true

  import App.Accounts.Fixtures

  alias App.Accounts.Models.UserToken
  alias App.Accounts.Services.TokenService

  setup do
    {:ok, user: user_fixture()}
  end

  test "a link works once, for the user it was made for", %{user: user} do
    secret = TokenService.issue(user.id, "reset")
    assert {:ok, user_id} = TokenService.consume(secret, "reset")
    assert user_id == user.id
    assert {:error, :invalid} = TokenService.consume(secret, "reset")
  end

  test "only a hash is kept", %{user: user} do
    secret = TokenService.issue(user.id, "reset")

    assert [%UserToken{token_hash: hash}] =
             Repo.all(from t in UserToken, where: t.user_id == ^user.id)

    refute hash == secret
    assert hash == :sha256 |> :crypto.hash(secret) |> Base.encode16(case: :lower)
    assert byte_size(secret) >= 43
  end

  test "a reset link is not a confirmation link, and the other way round", %{user: user} do
    reset = TokenService.issue(user.id, "reset")
    confirm = TokenService.issue(user.id, "confirm")
    assert {:error, :invalid} = TokenService.consume(reset, "confirm")
    assert {:error, :invalid} = TokenService.consume(confirm, "reset")
    assert {:ok, _} = TokenService.consume(reset, "reset")
    assert {:ok, _} = TokenService.consume(confirm, "confirm")
  end

  test "an expired link does not work", %{user: user} do
    secret = TokenService.issue(user.id, "reset")
    past = DateTime.add(DateTime.utc_now(), -1, :second)
    Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id), set: [expires_at: past])
    assert {:error, :invalid} = TokenService.consume(secret, "reset")
  end

  test "a new link replaces the one before it", %{user: user} do
    first = TokenService.issue(user.id, "reset")
    second = TokenService.issue(user.id, "reset")
    assert {:error, :invalid} = TokenService.consume(first, "reset")
    assert {:ok, _} = TokenService.consume(second, "reset")
  end

  test "nothing that is not a secret works", %{user: user} do
    TokenService.issue(user.id, "reset")

    for bad <- ["", "nope", nil, 5, %{}, String.duplicate("x", 5_000), "' OR 1=1 --"] do
      assert {:error, :invalid} = TokenService.consume(bad, "reset"), inspect(bad)
    end
  end

  test "issued_within? knows about a link just made", %{user: user} do
    refute TokenService.issued_within?(user.id, "reset", 60)
    TokenService.issue(user.id, "reset")
    assert TokenService.issued_within?(user.id, "reset", 60)
    refute TokenService.issued_within?(user.id, "confirm", 60)
  end

  test "prune forgets old links and keeps recent ones", %{user: user} do
    old = TokenService.issue(user.id, "confirm")
    TokenService.consume(old, "confirm")

    Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -8 * 86_400, :second)]
    )

    fresh = TokenService.issue(user.id, "reset")

    assert TokenService.prune() >= 1
    assert {:ok, _} = TokenService.consume(fresh, "reset")
  end
end
