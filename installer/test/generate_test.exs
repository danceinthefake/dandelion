defmodule DandelionNew.GenerateTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Dandelion.New

  defp files(app, module, example? \\ true, frontend? \\ true),
    do: Map.new(New.generate(app, module, example?, frontend?))

  defp secrets(files) do
    files
    |> Map.values()
    |> Enum.flat_map(
      &Regex.scan(~r/(?:secret_key_base|signing_salt): "([^"]+)"/, &1, capture: :all_but_first)
    )
    |> List.flatten()
  end

  test "renames the app everywhere; module names follow the folders" do
    files = files("my_app", "MyApp")

    assert files["mix.exs"] =~ "defmodule MyApp.MixProject"
    assert files["mix.exs"] =~ "app: :my_app,"
    assert files["config/dev.exs"] =~ "database: \"my_app_dev\""
    assert files["compose.yaml"] =~ "container_name: my_app-pg"
    assert files["lib/platform/database/repo.ex"] =~ "otp_app: :my_app"

    assert files["lib/app/shop/services/order_service.ex"] =~
             "defmodule App.Shop.Services.OrderService"

    for {path, contents} <- files do
      refute path =~ ~r/acme/i, path
      refute contents =~ ~r/acme/i, "#{path} still mentions acme"
    end
  end

  test "names containing 'acme' are renamed once, not twice" do
    admin = files("acme_admin", "AcmeAdmin")
    assert admin["mix.exs"] =~ "defmodule AcmeAdmin.MixProject"
    assert admin["mix.exs"] =~ "app: :acme_admin,"
  end

  test "every project gets its own secrets, never the example's" do
    example = secrets(Map.new(DandelionNew.Templates.all()))
    a = secrets(files("a_app", "AApp"))
    b = secrets(files("b_app", "BApp"))

    assert length(a) == 2
    assert MapSet.disjoint?(MapSet.new(a), MapSet.new(example))
    assert MapSet.disjoint?(MapSet.new(a), MapSet.new(b))

    assert Enum.all?(
             Enum.zip(Enum.sort_by(a, &byte_size/1), Enum.sort_by(example, &byte_size/1)),
             fn {x, y} -> byte_size(x) == byte_size(y) end
           )
  end

  test "--no-example keeps the layout and drops the orders example" do
    files = files("my_app", "MyApp", false)

    refute Enum.any?(Map.keys(files), &(&1 =~ ~r/orders?[._]|app\/shop/))
    assert Map.has_key?(files, "lib/app/.gitkeep")
    assert Map.has_key?(files, "lib/platform/web/fallback_handler.ex")
    refute files["lib/platform/web/router.ex"] =~ "/orders"
    refute files["lib/platform/cron.ex"] =~ "ExpireUnpaidOrders"
    refute files["config/runtime.exs"] =~ "ExpireUnpaidOrders"
    refute files["README.md"] =~ "orders"
    # the test catalogue needs the example's products table
    refute files["test/test_helper.exs"] =~ "products"
    assert files["test/test_helper.exs"] =~ "ExUnit.start()"
  end

  test "the frontend is part of the default project" do
    files = files("my_app", "MyApp")

    assert files["assets/package.json"] =~ "my_app-ui"
    assert files["lib/platform/web/router.ex"] =~ "PageHandler"
    assert files["Dockerfile"] =~ "AS ui"
    assert files[".gitignore"] =~ "/priv/static/app/"
    assert files["README.md"] =~ "assets/"
  end

  test "--no-frontend drops the Vue app and everything that builds or serves it" do
    files = files("my_app", "MyApp", true, false)

    refute Enum.any?(Map.keys(files), &String.starts_with?(&1, "assets/"))
    refute Map.has_key?(files, "lib/platform/web/page_handler.ex")
    refute files["lib/platform/web/router.ex"] =~ "PageHandler"
    refute files["Dockerfile"] =~ ~r/AS ui|node:|@frontend/
    refute files[".gitignore"] =~ "Vue"
    refute files["README.md"] =~ "Node"
    # the API, the socket and the example stay
    assert files["lib/platform/web/router.ex"] =~ "/orders"
    assert files["lib/platform/web/user_socket.ex"] =~ "OrderFeedChannel"
  end

  test "--no-example also drops the frontend and the order channel" do
    files = files("my_app", "MyApp", false)

    refute Enum.any?(Map.keys(files), &String.starts_with?(&1, "assets/"))
    refute files["lib/platform/web/router.ex"] =~ "PageHandler"
    refute files["lib/platform/web/user_socket.ex"] =~ "OrderFeedChannel"
    assert files["lib/platform/web/user_socket.ex"] =~ "def connect"
  end

  test "a generated project takes dandelion from hex, and has no checkout-only parts" do
    files = files("my_app", "MyApp")

    assert files["mix.exs"] =~ ~s({:dandelion, "~> 0.2.0"},)
    assert files["test/test_helper.exs"] =~ "products"
    refute files["mix.exs"] =~ "DANDELION_PATH"
    refute files["Dockerfile"] =~ "vendor/dandelion"
    refute Map.has_key?(files, "deploy/vendor-dandelion.sh")
    refute files["deploy/compose.cluster.yaml"] =~ "vendor-dandelion"
  end

  test "tracing is part of every project, renamed with it" do
    for example? <- [true, false] do
      files = files("my_app", "MyApp", example?, example?)

      assert files["mix.exs"] =~ ~S({:opentelemetry_phoenix, "~> 2.0"})
      assert files["mix.exs"] =~ "[my_app: [applications: [opentelemetry_exporter: :permanent"
      assert files["lib/platform/application.ex"] =~ "OpentelemetryOban.setup"
      assert files["config/runtime.exs"] =~ ~S[System.get_env("OTEL_SERVICE_NAME", "my_app")]
      assert files["rel/env.sh.eex"] =~ "service.instance.id"
      assert files["deploy/compose.cluster.yaml"] =~ "jaegertracing/jaeger"
      assert files["deploy/cluster-proof.sh"] =~ ~s(echo "traces:")
      # the cross-node trace needs orders: only with the example
      assert files["deploy/cluster-proof.sh"] =~ "one trace, two nodes" == example?
    end
  end

  test "the example has logins: an accounts domain, guarded routes, a token socket" do
    files = files("my_app", "MyApp")

    assert files["lib/app/accounts/handlers/auth.ex"] =~ "defmodule App.Accounts.Handlers.Auth"
    assert files["lib/platform/web/router.ex"] =~ "pipeline :authenticated"
    assert files["lib/platform/web/router.ex"] =~ "pipe_through [:api, :authenticated, :admin]"
    assert files["lib/platform/web/user_socket.ex"] =~ ~S(def connect(%{"token" => token})
    assert files["priv/repo/seeds.exs"] =~ "admin@example.com"
    assert files["config/test.exs"] =~ "App.Accounts.Services.Password"
    assert Enum.any?(Map.keys(files), &(&1 =~ "create_users"))
  end

  test "--no-example has no accounts, no login and no shop left in it" do
    files = files("my_app", "MyApp", false)

    for {path, contents} <- files do
      refute path =~ ~r/accounts|users/, path

      refute contents =~ ~r/App\.Accounts|App\.Shop/,
             "#{path} still mentions the example"
    end

    socket = files["lib/platform/web/user_socket.ex"]
    assert socket =~ "def connect(_params, socket, _connect_info)"
    refute socket =~ "token"

    # `mix setup` runs the seeds: they must not name a module the project lacks
    refute files["priv/repo/seeds.exs"] =~ "Product"
    refute files["config/test.exs"] =~ "Password"
  end

  test "marker lines never reach a generated project; left-out parts go whole" do
    for {example?, frontend?} <- [{true, true}, {true, false}, {false, false}] do
      files = files("my_app", "MyApp", example?, frontend?)

      for {path, contents} <- files do
        refute contents =~ ~r/@(example|frontend|dev)-(start|end)/, "#{path} keeps a marker"
      end

      proof = files["deploy/cluster-proof.sh"]
      assert proof =~ "node failure:"
      assert proof =~ "database outage:"
      assert proof =~ "echo \"events:\"" == example?
      assert proof =~ "serves the Vue app" == frontend?
      assert files["deploy/README.md"] =~ "PAYMENT_WEBHOOK_TOKEN" == example?
    end
  end

  describe "mix dandelion.new" do
    @tag :tmp_dir
    test "writes the project and makes the release scripts executable", %{tmp_dir: dir} do
      path = Path.join(dir, "my_app")
      Mix.shell(Mix.Shell.Process)
      New.run([path])

      assert File.read!(Path.join(path, "mix.exs")) =~ "app: :my_app,"

      for bin <- [
            "rel/overlays/bin/migrate",
            "deploy/cluster-proof.sh",
            "deploy/seed.sh",
            "deploy/partition-proof.sh",
            "deploy/failure-proof.sh"
          ] do
        assert File.stat!(Path.join(path, bin)).mode |> Bitwise.band(0o111) != 0, bin
      end

      assert_received {:mix_shell, :info, [msg]}
      assert msg =~ "Created my_app"
    end

    @tag :tmp_dir
    test "refuses bad names and non-empty directories", %{tmp_dir: dir} do
      assert_raise Mix.Error, ~r/App name/, fn -> New.run([Path.join(dir, "MyApp")]) end

      assert_raise Mix.Error, ~r/Module name/, fn ->
        New.run([Path.join(dir, "ok"), "--module", "my.App"])
      end

      File.write!(Path.join(dir, "taken.txt"), "x")
      assert_raise Mix.Error, ~r/isn't empty/, fn -> New.run([dir, "--app", "taken"]) end
    end
  end
end
