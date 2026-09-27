defmodule Mix.Tasks.Dandelion.New do
  @shortdoc "Creates an Elixir service laid out the way a Go service is"
  @moduledoc """
  Creates a new service: a JSON API with router → handlers → services →
  repos → models, Postgres, tests, a background job and a release
  Dockerfile. See https://github.com/danceinthefake/dandelion.

      mix dandelion.new PATH [--app APP] [--module MODULE] [--no-example]

    * `--app` — OTP app name (default: the directory name), e.g. `my_app`
    * `--module` — the project module (default: from the app name), e.g.
      `MyApp` for `MyApp.MixProject`; other modules follow the folders
    * `--no-example` — leave out the `orders` example; keep the layout

  The generated project is a copy of dandelion's tested example service with
  its names changed and fresh secrets.
  """
  use Mix.Task

  alias DandelionNew.Templates

  @switches [app: :string, module: :string, example: :boolean]

  # The example domain (`shop`): left out with --no-example.
  @example_prefixes ~w(lib/app/shop/ test/app/shop/ test/support/app/shop/)
  @example_files ~w(priv/repo/migrations/20260927000001_create_orders.exs)

  @impl true
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: @switches)

    path =
      case args do
        [path] ->
          path

        _ ->
          Mix.raise("Usage: mix dandelion.new PATH [--app APP] [--module MODULE] [--no-example]")
      end

    app = opts[:app] || path |> Path.expand() |> Path.basename()
    module = opts[:module] || Macro.camelize(app)
    example? = Keyword.get(opts, :example, true)

    check_names!(app, module)
    check_target!(path)

    files = generate(app, module, example?)

    for {file, contents} <- files do
      target = Path.join(path, file)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, contents)
    end

    for bin <- ["rel/overlays/bin/server", "rel/overlays/bin/migrate"],
        do: File.chmod!(Path.join(path, bin), 0o755)

    Mix.shell().info("""

    Created #{app} in #{path} (#{length(files)} files).

        cd #{path}
        mise install              # Erlang + Elixir from mise.toml
        docker compose up -d      # Postgres on localhost:55432
        mix setup                 # dependencies + database
        mix test
        mix phx.server            # http://localhost:4000

    New to Elixir from Go? Start with the phrasebook:
    https://github.com/danceinthefake/dandelion/tree/main/phrasebook
    """)
  end

  @doc false
  # [{path, contents}] for a new project. Pure — used by the tests.
  def generate(app, module, example? \\ true) do
    rename = &rename(&1, app, module)
    secrets = %{}

    templates =
      if example?,
        do: Templates.all(),
        else: Enum.reject(Templates.all(), fn {file, _} -> example_file?(file) end)

    {files, _} =
      Enum.map_reduce(templates, secrets, fn {file, contents}, secrets ->
        contents = if example?, do: contents, else: without_example(file, contents)
        {contents, secrets} = fresh_secrets(contents, secrets)
        {{rename.(file), format(file, rename.(contents))}, secrets}
      end)

    keep = if example?, do: [], else: [{"lib/app/.gitkeep", ""}]

    files ++ keep ++ [{"README.md", readme(app, example?)}]
  end

  defp example_file?(file),
    do: file in @example_files or String.starts_with?(file, @example_prefixes)

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

  # --no-example: remove the example's routes, job and job config. Each edit
  # must find its text — if the example changes, generation fails loudly
  # (and the tests catch it) instead of producing a broken project.
  defp without_example("lib/platform/web/router.ex", contents) do
    replace!(
      contents,
      ~r/  # domain: shop\n  scope "\/api" do\n.*?\n  end\n/s,
      """
        # domain: things (lib/app/things/)
        scope "/api" do
          pipe_through :api

          # get "/things/:id", App.Things.Handlers.ThingHandler, :show
        end
      """
    )
  end

  defp without_example("lib/platform/application.ex", contents) do
    replace!(
      contents,
      ~r/  defp jobs do\n.*?\n  end\n/s,
      "  defp jobs do\n    # e.g. [{App.Things.Workers.SomeWorker, []}]\n    []\n  end\n"
    )
  end

  defp without_example("config/runtime.exs", contents) do
    replace!(contents, ~r/# ≈ envconfig.*?enabled: config_env\(\) != :test\n\n/s, "")
  end

  defp without_example(_file, contents), do: contents

  defp replace!(contents, regex, replacement) do
    if Regex.match?(regex, contents),
      do: Regex.replace(regex, contents, replacement, global: false),
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

  defp readme(app, example?) do
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

    Module names follow the folders: `lib/app/shop/services/order_service.ex`
    is `App.Shop.Services.OrderService`.
    #{if example?, do: "\nThe `shop` domain (`lib/app/shop/`: orders, their handlers, services, repos and a worker) shows every layer; delete it when you don't need it.\n", else: ""}
    ## Run it

    ```sh
    mise install              # Erlang + Elixir (mise.toml)
    docker compose up -d      # Postgres on localhost:55432
    mix setup                 # dependencies + database
    mix test
    mix credo --strict
    mix phx.server            # http://localhost:4000
    ```

    ## Release

    ```sh
    docker build -t #{app} .
    docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… #{app} /app/bin/migrate
    docker run -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e PHX_HOST=… -p 4000:4000 #{app}
    ```

    Plain-HTTP requests are redirected to HTTPS in production (behind a load
    balancer that sets `x-forwarded-proto`); `GET /health` is left alone for
    probes. Services calling this one over plain HTTP inside your network?
    Remove `force_ssl` from `config/prod.exs`.

    Coming from Go? The [phrasebook](https://github.com/danceinthefake/dandelion/tree/main/phrasebook)
    maps each Go habit to the Elixir way.
    """
  end
end
