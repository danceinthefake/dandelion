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
    refute files["lib/app/router.ex"] =~ "/orders"
    refute files["lib/app/router.ex"] =~ "Accounts"
    refute files["lib/app/router.ex"] =~ "Webhooks"
    refute files["lib/app/router.ex"] =~ "Settings"
    refute files["lib/app/router.ex"] =~ "Files"
    refute files["lib/app/router.ex"] =~ "Audit"
    refute files["lib/app/router.ex"] =~ "Notifications"
    refute files["mix.exs"] =~ "swoosh"
    refute files["config/runtime.exs"] =~ "SMTP"
    refute files["deploy/compose.cluster.yaml"] =~ "mailpit"
    refute Map.has_key?(files, "lib/platform/mailer.ex")
    refute files["config/config.exs"] =~ "uploads_dir"
    refute files["Dockerfile"] =~ "uploads"
    refute files["deploy/compose.cluster.yaml"] =~ "uploads"
    refute files["mix.exs"] =~ ":req"
    refute files["config/config.exs"] =~ "webhook"
    refute files["config/runtime.exs"] =~ "WEBHOOK"
    refute files["deploy/compose.cluster.yaml"] =~ "hook-receiver"
    refute files["lib/platform/queue.ex"] =~ "webhooks"
    refute Enum.any?(Map.keys(files), &(&1 =~ "webhook"))
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
    assert files["lib/platform/web/routes.ex"] =~ "PageHandler"
    assert files["Dockerfile"] =~ "AS ui"
    assert files[".gitignore"] =~ "/priv/static/app/"
    assert files["README.md"] =~ "assets/"
  end

  test "--no-frontend drops the Vue app and everything that builds or serves it" do
    files = files("my_app", "MyApp", true, false)

    refute Enum.any?(Map.keys(files), &String.starts_with?(&1, "assets/"))
    refute Map.has_key?(files, "lib/platform/web/page_handler.ex")
    refute files["lib/platform/web/routes.ex"] =~ "PageHandler"
    refute files["Dockerfile"] =~ ~r/AS ui|node:|@frontend/
    refute files[".gitignore"] =~ "Vue"
    refute files["README.md"] =~ "Node"
    # the API, the socket and the example stay
    assert files["lib/app/shop/routes.ex"] =~ "/orders"
    assert files["lib/platform/web/user_socket.ex"] =~ "OrderFeedChannel"
  end

  test "--no-example also drops the frontend and the order channel" do
    files = files("my_app", "MyApp", false)

    refute Enum.any?(Map.keys(files), &String.starts_with?(&1, "assets/"))
    refute files["lib/platform/web/routes.ex"] =~ "PageHandler"
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

  test "the example sends webhooks: a domain, a signed delivery, a receiver to try it on" do
    files = files("my_app", "MyApp")

    assert files["lib/app/webhooks/workers/deliver.ex"] =~ "Dandelion.Resilience"
    assert files["lib/app/router.ex"] =~ "App.Webhooks.Routes.routes()"
    assert files["mix.exs"] =~ ~S({:req, "~> 0.5"})
    assert files["lib/platform/queue.ex"] =~ "webhooks: 5"
    assert files["lib/platform/pubsub.ex"] =~ "FanOut"
    assert files["deploy/compose.cluster.yaml"] =~ "hook-receiver"
    assert files["deploy/webhook-proof.sh"] =~ "webhook proof passed"
    assert files["config/runtime.exs"] =~ "WEBHOOK_ALLOW_PRIVATE"
    refute files["mix.exs"] =~ "@example"
  end

  test "every project can change settings while running; the example has the admin API for it" do
    for example? <- [true, false] do
      files = files("my_app", "MyApp", example?, example?)

      assert files["lib/platform/application.ex"] =~ "{Dandelion.Flags, repo:"

      assert files["priv/repo/migrations/20261008000003_add_flags.exs"] =~
               "Dandelion.Flags.Migration"

      assert Map.has_key?(files, "lib/app/settings/handlers/flag_handler.ex") == example?
    end
  end

  test "the example takes uploads: a files domain, a shared directory in the cluster" do
    files = files("my_app", "MyApp")

    assert files["lib/app/files/services/file_service.ex"] =~ "Dandelion.Storage.Local"
    assert files["lib/app/router.ex"] =~ "App.Files.Routes.routes()"
    assert files["deploy/compose.cluster.yaml"] =~ ~s("uploads:/data/uploads")
    assert files["Dockerfile"] =~ "/data/uploads"
    assert files["config/runtime.exs"] =~ "UPLOADS_DIR"
    assert files["deploy/uploads-proof.sh"] =~ "uploads proof passed"
    refute files["Dockerfile"] =~ "@example"
  end

  test "the example sends mail: a mailer, a record of what was sent, a mail server to try it on" do
    files = files("my_app", "MyApp")

    assert files["lib/platform/mailer.ex"] =~ "Swoosh.Mailer"
    assert files["lib/app/notifications/services/email_service.ex"] =~ "Dandelion.Resilience"
    assert files["lib/app/shop/workers/send_order_confirmation.ex"] =~ "EmailService.send_once"
    assert files["mix.exs"] =~ ~S({:swoosh, "~> 1.17"})
    assert files["config/runtime.exs"] =~ "SMTP_HOST"
    assert files["lib/platform/queue.ex"] =~ "mail: 5"
    assert files["deploy/compose.cluster.yaml"] =~ "axllent/mailpit"
    assert files["deploy/email-proof.sh"] =~ "email proof passed"
    refute files["config/runtime.exs"] =~ "@example-"
  end

  test "every project gets Prometheus, Grafana and the dashboard; the example gets the proof of it" do
    for example? <- [true, false] do
      files = files("my_app", "MyApp", example?, example?)

      assert files["deploy/compose.cluster.yaml"] =~ "grafana/grafana"
      assert files["deploy/compose.cluster.yaml"] =~ "prom/prometheus"
      assert files["deploy/prometheus.yml"] =~ "node1:4000"
      assert files["deploy/grafana/dashboards/dandelion.json"] =~ "\"uid\": \"dandelion\""
      assert files["config/prod.exs"] =~ ~s("/metrics")
      assert Map.has_key?(files, "deploy/dashboard-proof.sh") == example?
    end
  end

  test "the console has a page for each thing, and none of them puts text on the page as HTML" do
    files = files("my_app", "MyApp")

    for page <-
          ~w(Products Audit Settings Webhooks Files SignIn Register ForgotPassword ResetPassword ConfirmEmail Orders) do
      assert Map.has_key?(files, "assets/src/pages/#{page}Page.vue"), page
    end

    assert files["assets/src/router.ts"] =~ "hashchange"
    assert files["assets/src/highlight.test.ts"] =~ "html in the text stays text"
    assert files["assets/package.json"] =~ "node --test"

    # text is text: no v-html in any of the console's source
    for {name, source} <- files,
        String.starts_with?(name, "assets/src/") and String.ends_with?(name, ".vue") do
      refute source =~ "v-html=", name
    end

    bare = files("my_app", "MyApp", true, false)
    refute Enum.any?(Map.keys(bare), &String.starts_with?(&1, "assets/"))
  end

  test "the example's accounts can reset a password, confirm an address and lock a guessed one" do
    files = files("my_app", "MyApp")

    assert files["lib/app/accounts/services/token_service.ex"] =~ "SHA-256"
    assert files["lib/app/accounts/services/login_throttle.ex"] =~ "FOR UPDATE"
    assert files["lib/app/accounts/workers/send_account_email.ex"] =~ "send_once_lazy"

    assert files["priv/repo/migrations/20261012000001_add_account_security.exs"] =~
             "login_throttle"

    assert files["deploy/accounts-proof.sh"] =~ "accounts proof passed"
    assert files["deploy/backup.sh"] =~ "pg_dump"
    assert files["deploy/restore.sh"] =~ "pg_restore"
    assert files["deploy/backup-proof.sh"] =~ "backup proof passed"
    assert files["lib/platform/cron.ex"] =~ "PruneAccountTables"

    bare = files("my_app", "MyApp", false)
    refute bare["lib/platform/cron.ex"] =~ "PruneAccountTables"
    refute Map.has_key?(bare, "lib/app/accounts/services/token_service.ex")
  end

  test "the example can build a second version of itself, to prove a deploy that changes the database" do
    files = files("my_app", "MyApp")
    assert files["deploy/versions/order-channel.patch"] =~ "add_order_channel"
    assert files["deploy/upgrade-proof.sh"] =~ "upgrade proof passed"
    assert files["deploy/compose.cluster.yaml"] =~ "APP_SOURCE"

    bare = files("my_app", "MyApp", false)
    refute Map.has_key?(bare, "deploy/versions/order-channel.patch")
    refute Map.has_key?(bare, "deploy/upgrade-proof.sh")
  end

  test "the example searches its products with Postgres full-text search" do
    files = files("my_app", "MyApp")

    assert files["priv/repo/migrations/20261010000001_add_product_search.exs"] =~
             "Dandelion.Search.Migration.add_index"

    assert files["lib/app/shop/handlers/product_search_handler.ex"] =~ "ProductService.search"
    assert files["lib/app/shop/services/product_service.ex"] =~ "Dandelion.Search.search"
    assert files["deploy/search-proof.sh"] =~ "search proof passed"

    bare = files("my_app", "MyApp", false)
    refute Map.has_key?(bare, "lib/app/shop/handlers/product_search_handler.ex")
    refute Map.has_key?(bare, "priv/repo/migrations/20261010000001_add_product_search.exs")
  end

  test "every project keeps an audit log; the example records its admin actions and serves the log" do
    for example? <- [true, false] do
      files = files("my_app", "MyApp", example?, example?)

      assert files["lib/platform/application.ex"] =~ "{Dandelion.Audit, repo:"

      assert files["priv/repo/migrations/20261009000001_add_audit.exs"] =~
               "Dandelion.Audit.Migration"

      assert Map.has_key?(files, "lib/app/audit/handlers/audit_handler.ex") == example?
      assert Map.has_key?(files, "deploy/audit-proof.sh") == example?
    end
  end

  test "the example has logins: an accounts domain, guarded routes, a token socket" do
    files = files("my_app", "MyApp")

    assert files["lib/app/accounts/handlers/auth.ex"] =~ "defmodule App.Accounts.Handlers.Auth"
    assert files["lib/app/router.ex"] =~ "pipeline :authenticated"
    assert files["lib/app/shop/routes.ex"] =~ "pipe_through [:api, :authenticated, :admin]"
    assert files["lib/app/router.ex"] =~ "App.Shop.Routes.routes()"
    refute files["lib/app/router.ex"] =~ "/orders"
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
