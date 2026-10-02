defmodule Mix.Tasks.Dandelion.New do
  @shortdoc "Creates an Elixir service laid out the way a Go service is"
  @moduledoc """
  Creates a new service: a JSON API with router → handlers → services →
  repos → models, Postgres, tests, a background job and a release
  Dockerfile. See https://github.com/danceinthefake/dandelion.

      mix dandelion.new PATH [--app APP] [--module MODULE] [--no-example] [--no-frontend]

    * `--app` — OTP app name (default: the directory name), e.g. `my_app`
    * `--module` — the project module (default: from the app name), e.g.
      `MyApp` for `MyApp.MixProject`; other modules follow the folders
    * `--no-example` — leave out the `orders` example (and with it the
      Vue frontend, which is the example's UI); keep the layout
    * `--no-frontend` — leave out the Vue + blessing-ui frontend (`assets/`),
      so no Node is needed; the API and the WebSocket stay

  The generated project is a copy of dandelion's tested example service with
  its names changed and fresh secrets.
  """
  use Mix.Task

  alias DandelionNew.Templates

  @switches [app: :string, module: :string, example: :boolean, frontend: :boolean]

  # The example domain (`shop`): left out with --no-example.
  @example_prefixes ~w(
    lib/app/shop/ test/app/shop/ test/support/app/shop/
    lib/app/accounts/ test/app/accounts/ test/support/app/accounts/
  )
  @example_files ~w(
    priv/repo/migrations/20260927000001_create_orders.exs
    priv/repo/migrations/20260930000001_refunds_and_customer_stats.exs
    priv/repo/migrations/20260930000002_create_products.exs
    priv/repo/migrations/20261002000001_create_users.exs
    priv/repo/migrations/20261002000002_add_user_to_orders.exs
    deploy/seed.sh
    deploy/partition-proof.sh
    test/platform/pubsub_test.exs
  )

  # Only for working inside a dandelion checkout: never in a generated project.
  @dev_files ~w(deploy/vendor-dandelion.sh)

  # The Vue app: left out with --no-frontend (and --no-example).
  @frontend_prefixes ~w(assets/)
  @frontend_files ~w(lib/platform/web/page_handler.ex)

  @impl true
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: @switches)

    path =
      case args do
        [path] ->
          path

        _ ->
          Mix.raise(
            "Usage: mix dandelion.new PATH [--app APP] [--module MODULE] [--no-example] [--no-frontend]"
          )
      end

    app = opts[:app] || path |> Path.expand() |> Path.basename()
    module = opts[:module] || Macro.camelize(app)
    example? = Keyword.get(opts, :example, true)
    frontend? = example? and Keyword.get(opts, :frontend, true)

    check_names!(app, module)
    check_target!(path)

    files = generate(app, module, example?, frontend?)

    for {file, contents} <- files do
      target = Path.join(path, file)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, contents)
    end

    # (the example's scripts are left out with --no-example)
    for bin <- ~w(rel/overlays/bin/server rel/overlays/bin/migrate
                  deploy/cluster-proof.sh deploy/seed.sh deploy/partition-proof.sh),
        File.exists?(Path.join(path, bin)),
        do: File.chmod!(Path.join(path, bin), 0o755)

    Mix.shell().info("""

    Created #{app} in #{path} (#{length(files)} files).

        cd #{path}
        mise install              # Erlang + Elixir from mise.toml
        docker compose up -d      # Postgres on localhost:55432
        mix setup                 # dependencies + database
        mix test
        #{if frontend?, do: "(cd assets && npm install && npm run build)   # the Vue app, needs Node\n    ", else: ""}mix phx.server            # http://localhost:4000

    New to Elixir from Go? Start with the phrasebook:
    https://github.com/danceinthefake/dandelion/tree/main/phrasebook
    """)
  end

  @doc false
  # [{path, contents}] for a new project. Pure — used by the tests.
  def generate(app, module, example? \\ true, frontend? \\ true) do
    frontend? = example? and frontend?
    rename = &rename(&1, app, module)
    secrets = %{}

    templates =
      Enum.reject(Templates.all(), fn {file, _} ->
        file in @dev_files or (not example? and example_file?(file)) or
          (not frontend? and frontend_file?(file))
      end)

    {files, _} =
      Enum.map_reduce(templates, secrets, fn {file, contents}, secrets ->
        contents = if example?, do: contents, else: without_example(file, contents)
        contents = if frontend?, do: contents, else: without_frontend(file, contents)
        contents = hex_dependency(file, contents) |> blocks(example?, frontend?)
        {contents, secrets} = fresh_secrets(contents, secrets)
        {{rename.(file), format(file, rename.(contents))}, secrets}
      end)

    keep = if example?, do: [], else: [{"lib/app/.gitkeep", ""}]

    files ++ keep ++ [{"README.md", readme(app, example?, frontend?)}]
  end

  defp example_file?(file),
    do: file in @example_files or String.starts_with?(file, @example_prefixes)

  defp frontend_file?(file),
    do: file in @frontend_files or String.starts_with?(file, @frontend_prefixes)

  # The example's app is `acme` (`Acme.MixProject`); module names elsewhere
  # follow the folders (`Platform.*`, `App.Shop.*`) and don't change. One
  # pass, so a name like `acme_admin` can't be renamed twice.
  defp rename(text, app, module) do
    Regex.replace(~r/Acme|acme/, text, fn
      "Acme" -> module
      "acme" -> app
    end)
  end

  # Renaming changes line lengths; re-format with the project's own rules.
  defp format(file, contents) do
    case Templates.formatter_opts(file) do
      nil -> contents
      opts -> IO.iodata_to_binary([Code.format_string!(contents, opts), "\n"])
    end
  end

  # Each project gets its own secret_key_base values and signing salts.
  defp fresh_secrets(contents, secrets) do
    Regex.scan(~r/(?:secret_key_base|signing_salt): "([^"]+)"/, contents, capture: :all_but_first)
    |> List.flatten()
    |> Enum.reduce({contents, secrets}, fn old, {contents, secrets} ->
      new = Map.get_lazy(secrets, old, fn -> random(byte_size(old)) end)
      {String.replace(contents, ~s("#{old}"), ~s("#{new}")), Map.put(secrets, old, new)}
    end)
  end

  defp random(length) do
    length
    |> :crypto.strong_rand_bytes()
    |> Base.encode64(padding: false)
    |> binary_part(0, length)
  end

  # --no-example: remove the example's routes, cron entry and job config. Each edit
  # must find its text — if the example changes, generation fails loudly
  # (and the tests catch it) instead of producing a broken project.
  defp without_example("lib/platform/web/router.ex", contents) do
    replace!(
      contents,
      ~r/  # domain: accounts.*\nend\n\z/s,
      """
        # domain: things (lib/app/things/)
        scope "/api" do
          pipe_through :api

          # get "/things/:id", App.Things.Handlers.ThingHandler, :show
        end
      end
      """
    )
  end

  # Without the example there is no login: the socket takes any connection
  # (put your own identity check in `connect/3`).
  defp without_example("lib/platform/web/user_socket.ex", contents) do
    contents
    |> replace!(
      ~r/  # domain: shop\n  channel "orders:\*", [\w.]+\n/,
      "  # domain: things\n  # channel \"things:*\", App.Things.Channels.ThingChannel\n"
    )
    |> replace!(~r/\n  alias App\.Accounts\.Handlers\.Token\n/, "")
    |> replace!(
      ~r/  @impl true\n  def connect\(%\{"token" => token\}.*?def connect\(_params, _socket, _connect_info\), do: :error\n/s,
      """
        @impl true
        def connect(_params, socket, _connect_info) do
          viewer_id = 6 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
          {:ok, assign(socket, :viewer_id, viewer_id)}
        end
      """
    )
    |> replace!(
      ~r/  A connection needs the login token.*?connection also gets a random `viewer_id` for the "who's online" list\./s,
      "  Every connection gets a random `viewer_id` (who's online needs a name; there is\n  no login here — put your own identity check in `connect/3`)."
    )
  end

  # Users and the demo products are the example's.
  defp without_example("priv/repo/seeds.exs", contents) do
    contents
    |> replace!(~r/\nalias App\.Shop\.Models\.Product\n.*\z/s, "")
    |> String.replace("App.Shop.Models.SomeSchema", "App.Things.Models.Thing")
  end

  defp without_example("config/test.exs", contents) do
    contents
    |> replace!(~r/\nconfig :acme, :payment_webhook_token, "test-token"\n/, "")
    |> replace!(~r/\n# fast password hashing in tests.*?iterations: 1_000\n/s, "")
  end

  defp without_example("deploy/README.md", contents),
    do: replace!(contents, ~r/\| `PAYMENT_WEBHOOK_TOKEN` \|[^\n]*\n/, "")

  # the catalogue the order tests use needs the products table
  defp without_example("test/test_helper.exs", contents),
    do: replace!(contents, ~r/# The catalogue.*?\n\nExUnit\.start\(\)/s, "ExUnit.start()")

  defp without_example("lib/platform/cron.ex", contents) do
    replace!(
      contents,
      ~r/    \[\n      # every minute: cancel orders.*?\n    \]\n/s,
      "    [\n      # e.g. {\"0 * * * *\", App.Things.Workers.HourlyCleanup}\n    ]\n"
    )
  end

  defp without_example("config/runtime.exs", contents) do
    contents
    |> replace!(~r/# ≈ envconfig.*?UNPAID_ORDER_MAX_AGE_SECONDS", "3600"\)\)\n\n/s, "")
    |> replace!(
      ~r/  config :acme,\n         :payment_webhook_token,\n.*?           """\)\n\n/s,
      ""
    )
  end

  defp without_example("config/dev.exs", contents),
    do: replace!(contents, ~r/\n# The payment provider's webhook token.*?"dev-token"\n/s, "")

  defp without_example("deploy/compose.cluster.yaml", contents),
    do: replace!(contents, ~r/    PAYMENT_WEBHOOK_TOKEN: [\w-]+\n/, "")

  defp without_example("lib/platform/pubsub.ex", contents) do
    contents
    |> replace!(~r/  alias App\.Shop\.Workers\.\{[^}]*\}\n\n/, "")
    |> replace!(
      ~r/    %\{\n      "order.created" => \[[^\]]*\]\n    \}\n/,
      "    %{\n      # \"thing.created\" => [App.Things.Workers.SendWelcome]\n    }\n"
    )
  end

  defp without_example(_file, contents), do: contents

  # The example takes the library from the checkout (a dev-only `dandelion/0`
  # in its mix.exs); a generated project takes it from hex.
  defp hex_dependency("mix.exs", contents),
    do: replace!(contents, ~r/dandelion\(\),/, ~S({:dandelion, "~> 0.2.0"},))

  defp hex_dependency(_file, contents), do: contents

  # Parts of a file that belong to the example or the frontend sit between
  # marker lines — `# @example-start` … `# @example-end` (also
  # `<!-- @frontend-start -->`). Kept, only the marker lines go; left out,
  # the whole part goes.
  defp blocks(contents, example?, frontend?) do
    contents
    |> block("example", example?)
    |> block("frontend", frontend?)
    |> block("dev", false)
  end

  defp block(contents, tag, keep?) do
    marker = ~r/^[ \t]*(?:#|<!--) @#{tag}-(?:start|end)(?: -->)?\n/m

    whole =
      ~r/^[ \t]*(?:#|<!--) @#{tag}-start(?: -->)?\n.*?^[ \t]*(?:#|<!--) @#{tag}-end(?: -->)?\n\n?/ms

    Regex.replace(if(keep?, do: marker, else: whole), contents, "")
  end

  # --no-frontend: no shell page, no Node stage in the Dockerfile.
  defp without_frontend("lib/platform/web/router.ex", contents),
    do: replace!(contents, ~r/  get "\/", Platform.Web.PageHandler, :index\n/, "")

  defp without_frontend(".gitignore", contents),
    do: replace!(contents, ~r/\n# Vue app\n.*?\/priv\/static\/app\/\n/s, "")

  defp without_frontend(_file, contents), do: contents

  defp replace!(contents, regex, replacement, opts \\ [global: false]) do
    if Regex.match?(regex, contents),
      do: Regex.replace(regex, contents, replacement, opts),
      else:
        Mix.raise(
          "dandelion.new: the template changed; can't remove the example from it (#{inspect(regex)})"
        )
  end

  defp check_names!(app, module) do
    unless app =~ ~r/\A[a-z][a-z0-9_]*\z/,
      do:
        Mix.raise(
          "App name must start with a letter and have only lowercase letters, numbers and _: #{inspect(app)}"
        )

    unless module =~ ~r/\A[A-Z][A-Za-z0-9]*\z/,
      do: Mix.raise("Module name must be one CamelCase word, e.g. MyApp: #{inspect(module)}")
  end

  defp check_target!(path) do
    if File.exists?(path) and File.ls!(path) != [],
      do: Mix.raise("#{path} already exists and isn't empty")
  end

  defp readme(app, example?, frontend?) do
    """
    # #{app}

    An Elixir service in two parts — `lib/platform/`, what every app runs on,
    and `lib/app/<domain>/`, your business, laid out the way a Go service is.
    Generated by [dandelion](https://github.com/danceinthefake/dandelion).

    | Go | here |
    |---|---|
    | `cmd/server/main.go` | `lib/platform/application.ex` (what starts, in order) |
    | `*sql.DB` | `lib/platform/database/repo.ex` |
    | chi router, middleware | `lib/platform/web/` — `router.ex` lists every route |
    | `internal/<domain>/http/` | `lib/app/<domain>/handlers/` |
    | `internal/<domain>/service/` | `lib/app/<domain>/services/` |
    | `internal/<domain>/repo/` | `lib/app/<domain>/repos/` |
    | `internal/<domain>/model/` | `lib/app/<domain>/models/` |
    | background goroutines | `lib/app/<domain>/workers/` |
    | `migrations/` | `priv/repo/migrations/` |

    Module names follow the folders: #{if example?, do: "`lib/app/shop/services/order_service.ex` is `App.Shop.Services.OrderService`", else: "`lib/app/billing/services/invoice_service.ex` would be `App.Billing.Services.InvoiceService`"}.
    #{if frontend?, do: "\nThe Vue + blessing-ui frontend is in `assets/` (built into `priv/static/app`, served at `/`): a live order feed, who's online, new order, order detail. It needs Node.\n", else: ""}#{if example?, do: "\nThe `shop` domain (`lib/app/shop/`: orders, their handlers, services, repos and a worker) shows every layer, and `accounts` (`lib/app/accounts/`) is a login with signed tokens, the plug that guards routes, and who may see what; delete or replace both when you don't need them.\n", else: ""}
    ## Add a resource

    ```sh
    mix dandelion.gen.domain Billing Invoice number:string amount_cents:integer
    mix ecto.migrate && mix test
    ```

    writes the model, repo, service, handler, migration, tests and routes for it
    in this layout#{if example?, do: ", behind the login", else: ""}.

    ## Run it

    ```sh
    mise install              # Erlang + Elixir (mise.toml)
    docker compose up -d      # Postgres on localhost:55432
    mix setup                 # dependencies + database
    mix test
    mix credo --strict
    mix phx.server            # http://localhost:4000
    ```
    #{if frontend?, do: "\nThe frontend: `cd assets && npm install && npm run build` once, then `mix phx.server`; or `npm run dev` (Vite on :5173, forwarding `/api` and `/socket` to Phoenix).\n", else: ""}
    ## Release

    ```sh
    docker build -t #{app} .
    docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… #{app} /app/bin/migrate
    docker run -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e RELEASE_COOKIE=… -e PHX_HOST=… -p 4000:4000 #{app}
    ```

    More than one node: `deploy/README.md` — a local 3-node cluster behind
    nginx, and what each node needs.

    Plain-HTTP requests are redirected to HTTPS in production (behind a load
    balancer that sets `x-forwarded-proto`); `GET /health` is left alone for
    probes. Services calling this one over plain HTTP inside your network?
    Remove `force_ssl` from `config/prod.exs`.

    Coming from Go? The [phrasebook](https://github.com/danceinthefake/dandelion/tree/main/phrasebook)
    maps each Go habit to the Elixir way.
    """
  end
end
