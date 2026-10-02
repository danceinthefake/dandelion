defmodule App.Shop.Channels.OrderFeedChannelTest do
  # not async: the channel processes use the test's database connection
  use Platform.DataCase, async: false

  import App.Accounts.Fixtures
  import App.Shop.Fixtures
  import Phoenix.ChannelTest

  alias App.Accounts.Handlers.Token
  alias App.Shop.Services.OrderService
  alias Platform.Web.UserSocket

  @endpoint Platform.Web.Endpoint

  defp token(user), do: Token.sign(user)

  defp join_feed(user \\ admin_fixture()) do
    {:ok, socket} = connect(UserSocket, %{"token" => token(user)})
    subscribe_and_join(socket, "orders:live", %{})
  end

  test "a connection needs a login token" do
    assert connect(UserSocket, %{}) == :error
    assert connect(UserSocket, %{"token" => "nope"}) == :error
    assert connect(UserSocket, %{"token" => 42}) == :error
    assert {:ok, _} = connect(UserSocket, %{"token" => token(user_fixture())})
  end

  test "the feed shows everyone's orders, so it is for admins" do
    {:ok, socket} = connect(UserSocket, %{"token" => token(user_fixture())})
    assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, "orders:live", %{})
  end

  test "joining replies with the latest orders, and the node it is connected to" do
    order = order_fixture()
    assert {:ok, %{orders: [%{id: id} | _], node: node}, _socket} = join_feed()
    assert id == order.id
    assert node == Atom.to_string(node())
  end

  test "an order made after joining is pushed" do
    {:ok, _reply, _socket} = join_feed()
    {:ok, order} = OrderService.create(order_params())

    assert_push "order", %{id: id, customer_email: "sari@example.com", total_cents: 7000}
    assert id == order.id
  end

  test "an unknown topic is refused" do
    {:ok, socket} = connect(UserSocket, %{"token" => token(admin_fixture())})
    assert {:error, %{reason: _}} = subscribe_and_join(socket, "orders:other", %{})
  end

  test "who is online: the joiner is in presence, and others see it arrive" do
    {:ok, _, _socket} = join_feed()
    assert_push "presence_state", %{}
    assert_push "presence_diff", %{joins: joins}
    assert map_size(joins) == 1

    {:ok, _, _other} = join_feed()
    assert_push "presence_diff", %{joins: joins}
    assert map_size(joins) == 1
  end

  test "a second viewer sees the first in presence_state" do
    {:ok, _, _first} = join_feed()
    assert_push "presence_state", %{}
    assert_push "presence_diff", _

    {:ok, _, _second} = join_feed()
    assert_push "presence_state", state
    assert map_size(state) == 1
  end
end
