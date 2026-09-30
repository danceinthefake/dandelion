defmodule Dandelion.QueueTest do
  use ExUnit.Case, async: false

  alias Dandelion.Queue

  @opts [otp_app: :queue_test_app, repo: MyRepo, crontab: [{"* * * * *", SomeWorker}]]

  test "defaults: two queues, the crontab, a lifeline and a pruner" do
    config = Queue.config(@opts)

    assert config[:repo] == MyRepo
    assert config[:queues] == [default: 10, ordered: 10]
    assert config[:cron] == [crontab: [{"* * * * *", SomeWorker}]]
    assert config[:lifeline] == [rescue_after: {5, :minutes}]
    assert config[:pruner] == [max_age: {7, :days}]
  end

  test "no crontab by default" do
    assert Queue.config(otp_app: :queue_test_app, repo: MyRepo)[:cron] == [crontab: []]
  end

  test "the app's config overrides" do
    Application.put_env(:queue_test_app, Oban, testing: :manual, queues: [default: 1])
    on_exit(fn -> Application.delete_env(:queue_test_app, Oban) end)

    config = Queue.config(@opts)
    assert config[:testing] == :manual
    assert config[:queues] == [default: 1]
    assert config[:repo] == MyRepo
  end
end
