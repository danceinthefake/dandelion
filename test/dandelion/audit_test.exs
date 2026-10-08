defmodule Dandelion.AuditTest do
  use Dandelion.DataCase, async: false

  alias Dandelion.Audit
  alias Dandelion.TestRepo

  setup do
    Audit.start_link(repo: TestRepo)
    :ok
  end

  defp tag, do: "t#{System.unique_integer([:positive])}"

  test "record, then list: newest first, with everything that was given" do
    t = tag()
    Audit.record("user:#{t}", "product.price_changed", "product:#{t}", %{from: 1, to: 2})
    Audit.record("user:#{t}", "order.cancelled", "order:#{t}")

    assert [%{action: "order.cancelled", details: %{}}, %{action: "product.price_changed"} = e] =
             Audit.list(actor: "user:#{t}")

    assert e.actor == "user:#{t}" and e.subject == "product:#{t}"
    assert e.details == %{"from" => 1, "to" => 2}
    assert %DateTime{} = e.at
  end

  test "filters: actor, subject, exact action, action family by prefix" do
    t = tag()
    Audit.record("user:#{t}", "order.cancelled", "order:#{t}")
    Audit.record("user:#{t}", "order.refunded", "order:#{t}")
    Audit.record("user:#{t}", "flag.changed", "flag:x#{t}")
    Audit.record("other:#{t}", "order.cancelled", "order:other#{t}")

    assert length(Audit.list(actor: "user:#{t}")) == 3
    assert [_, _] = Audit.list(actor: "user:#{t}", action: "order.")

    assert [%{action: "order.refunded"}] =
             Audit.list(actor: "user:#{t}", action: "order.refunded")

    assert [%{actor: "other:" <> _}] = Audit.list(subject: "order:other#{t}")
    # a prefix is only a prefix when it ends in a dot
    assert [] = Audit.list(actor: "user:#{t}", action: "order")
  end

  test "pages: before is the id of the last entry seen" do
    t = tag()
    for i <- 1..5, do: Audit.record("user:#{t}", "step.done", "step:#{i}")

    first = Audit.list(actor: "user:#{t}", limit: 2)
    assert Enum.map(first, & &1.subject) == ["step:5", "step:4"]
    second = Audit.list(actor: "user:#{t}", limit: 2, before: List.last(first).id)
    assert Enum.map(second, & &1.subject) == ["step:3", "step:2"]

    assert [%{subject: "step:1"}] =
             Audit.list(actor: "user:#{t}", limit: 2, before: List.last(second).id)
  end

  test "the limit is bounded" do
    assert length(Audit.list(limit: 100_000)) <= 200
    assert length(Audit.list(limit: 0)) <= 1
  end

  test "an entry made in a transaction that rolls back is gone with it" do
    t = tag()

    TestRepo.transaction(fn ->
      Audit.record("user:#{t}", "product.price_changed", "product:#{t}")
      TestRepo.rollback(:the_change_failed)
    end)

    assert [] = Audit.list(actor: "user:#{t}")
  end

  test "it is append-only: update, delete and truncate are refused" do
    t = tag()
    Audit.record("user:#{t}", "order.cancelled", "order:#{t}")

    for sql <- [
          "UPDATE dandelion_audit SET actor = 'someone-else'",
          "DELETE FROM dandelion_audit",
          "TRUNCATE dandelion_audit"
        ] do
      assert {:error, %Postgrex.Error{postgres: %{message: message}}} = TestRepo.query(sql)
      assert message =~ "append-only"
    end

    assert [_] = Audit.list(actor: "user:#{t}")
  end

  test "prune removes old entries, and only through prune" do
    t = tag()
    Audit.record("user:#{t}", "old.thing", "x:1")
    Process.sleep(5)
    cutoff = DateTime.utc_now()
    Process.sleep(5)
    Audit.record("user:#{t}", "new.thing", "x:2")

    assert Audit.prune(cutoff) >= 1
    assert [%{action: "new.thing"}] = Audit.list(actor: "user:#{t}")
    # the permission was for that transaction only
    assert {:error, _} = TestRepo.query("DELETE FROM dandelion_audit")
  end

  test "the request id of the process is stored" do
    t = tag()
    Logger.metadata(request_id: "req-#{t}")
    on_exit(fn -> Logger.metadata(request_id: nil) end)
    Audit.record("user:#{t}", "a.b", "x:1")
    assert [%{request_id: "req-" <> _}] = Audit.list(actor: "user:#{t}")
  end

  test "a malformed entry raises: that is a bug in the caller" do
    assert_raise ArgumentError, fn -> Audit.record("", "a.b", "x") end
    assert_raise ArgumentError, fn -> Audit.record("u", "Bad Action", "x") end
    assert_raise ArgumentError, fn -> Audit.record("u", "a.b", String.duplicate("x", 201)) end
    assert_raise ArgumentError, fn -> Audit.record("u", "a.b", "x", %{pid: self()}) end

    assert_raise ArgumentError, fn ->
      Audit.record("u", "a.b", "x", %{big: String.duplicate("x", 10_001)})
    end
  end
end
