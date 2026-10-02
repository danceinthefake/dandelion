defmodule App.Accounts.Services.PasswordTest do
  use ExUnit.Case, async: true

  alias App.Accounts.Services.Password

  test "a hash verifies its own password, and only that" do
    hash = Password.hash("correct horse battery")
    assert Password.verify("correct horse battery", hash)
    refute Password.verify("correct horse batterz", hash)
    refute Password.verify("", hash)
  end

  test "the hash carries its algorithm, iterations and a fresh salt" do
    [one, two] = [Password.hash("same password"), Password.hash("same password")]
    assert ["pbkdf2_sha256", iterations, salt, _hash] = String.split(one, "$")
    assert String.to_integer(iterations) > 0
    assert byte_size(Base.decode64!(salt, padding: false)) == 16
    assert one != two
  end

  test "an old hash with fewer iterations still verifies (the count is in the hash)" do
    salt = "0123456789abcdef"
    key = :crypto.pbkdf2_hmac(:sha256, "pw", salt, 10, 32)
    b64 = &Base.encode64(&1, padding: false)
    assert Password.verify("pw", Enum.join(["pbkdf2_sha256", 10, b64.(salt), b64.(key)], "$"))
  end

  test "garbage in the database is a no, not a crash" do
    for stored <- ["", "plain", "a$b$c$d", "pbkdf2_sha256$x$y$z", "pbkdf2_sha256$1$!!$!!"] do
      refute Password.verify("pw", stored), stored
    end
  end

  test "verify_nothing does the work and says no" do
    refute Password.verify_nothing()
  end
end
