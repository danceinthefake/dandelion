defmodule App.Accounts.Services.UserServiceTest do
  use Platform.DataCase, async: true

  import App.Accounts.Fixtures

  alias App.Accounts.Services.UserService

  defp errors(changeset), do: Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)

  describe "register/2" do
    test "creates a customer, keeps the email lower-case, never stores the password" do
      assert {:ok, user} =
               UserService.register(%{"email" => "  Sari@Example.COM ", "password" => password()})

      assert user.email == "sari@example.com"
      assert user.role == "customer"
      assert user.password_hash =~ "pbkdf2_sha256$"
      refute user.password_hash =~ password()
      assert is_nil(user.password)
    end

    test "the role is the caller's choice, not the request's" do
      assert {:ok, %{role: "customer"}} =
               UserService.register(%{
                 "email" => "a@example.com",
                 "password" => password(),
                 "role" => "admin"
               })

      assert {:ok, %{role: "admin"}} =
               UserService.register(
                 %{"email" => "b@example.com", "password" => password()},
                 "admin"
               )
    end

    test "rejects invalid input" do
      cases = [
        {%{}, %{email: ["can't be blank"], password: ["can't be blank"]}},
        {%{"email" => "sari", "password" => password()}, %{email: ["must be an email address"]}},
        {%{"email" => "a@example.com", "password" => "short"},
         %{password: ["should be at least %{count} character(s)"]}},
        {%{"email" => "a@example.com", "password" => String.duplicate("x", 201)},
         %{password: ["should be at most %{count} character(s)"]}}
      ]

      for {params, expected} <- cases do
        assert {:error, changeset} = UserService.register(params)
        assert errors(changeset) == expected, inspect(params)
      end
    end

    test "an email is registered once, whatever its case" do
      {:ok, _} = UserService.register(%{"email" => "dup@example.com", "password" => password()})

      assert {:error, changeset} =
               UserService.register(%{"email" => "DUP@example.com", "password" => password()})

      assert errors(changeset) == %{email: ["has already been taken"]}
    end
  end

  describe "authenticate/2" do
    test "the right email and password give the user, whatever the email's case" do
      user = user_fixture()
      assert {:ok, %{id: id}} = UserService.authenticate(user.email, password())
      assert id == user.id
      assert {:ok, %{id: ^id}} = UserService.authenticate(String.upcase(user.email), password())
    end

    test "a wrong password, an unknown email and odd input all give the same answer" do
      user = user_fixture()

      for {email, pw} <- [
            {user.email, "wrong password"},
            {"nobody@example.com", password()},
            {nil, password()},
            {user.email, nil},
            {%{"x" => 1}, [1, 2]}
          ] do
        assert UserService.authenticate(email, pw) == {:error, :unauthorized}
      end
    end
  end

  test "get/1 and admin?/1" do
    user = user_fixture()
    assert {:ok, %{id: id}} = UserService.get(user.id)
    assert id == user.id
    assert UserService.get(-1) == {:error, :not_found}
    refute UserService.admin?(user)
    assert UserService.admin?(admin_fixture())
  end
end
