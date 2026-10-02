defmodule Mix.Tasks.Dandelion.Gen.Domain do
  @shortdoc "Adds a resource to a domain: model, repo, service, handler, migration, tests, routes"
  @moduledoc """
  Adds one resource to a domain of a dandelion project, in the layout the
  project already uses — the way you'd copy `shop` and rename it, done for you.

      mix dandelion.gen.domain DOMAIN RESOURCE [field:type ...]

      mix dandelion.gen.domain Billing Invoice number:string amount_cents:integer paid:boolean

  writes (for domain `Billing`, resource `Invoice`):

      lib/app/billing/models/invoice.ex            schema + validation
      lib/app/billing/repos/invoice_repo.ex        queries, nothing else
      lib/app/billing/services/invoice_service.ex  business rules: create / get / list
      lib/app/billing/handlers/invoice_handler.ex  HTTP: params → service → JSON
      lib/app/billing/handlers/invoice_json.ex     the JSON shape
      priv/repo/migrations/<time>_create_invoices.exs
      test/app/billing/services/invoice_service_test.exs
      test/app/billing/handlers/invoice_handler_test.exs
      test/support/app/billing/invoice_fixtures.ex

  and adds `POST /api/invoices`, `GET /api/invoices`, `GET /api/invoices/:id`
  to `lib/platform/web/router.ex`. Then run `mix ecto.migrate` and `mix test`.

  Field types: `string` (up to 255 characters), `text` (up to 10 000),
  `integer` and `boolean` (false unless given). All fields are required except
  booleans. There must be at least one that isn't a boolean. `id`,
  `inserted_at` and `updated_at` come for free.

  The table is the resource's plural (`invoices`); it can be changed with
  `--table`. The task refuses to overwrite a file that exists.

  It does not know your business: it gives you the shape — create, show, list —
  and you add the rules (a cancel, a state change) the way `shop` does.
  """
  use Mix.Task

  @types %{
    "string" => %{ecto: "string", column: "text", max: "255"},
    "text" => %{ecto: "string", column: "text", max: "10_000"},
    "integer" => %{ecto: "integer", column: "bigint"},
    "boolean" => %{ecto: "boolean", column: "boolean"}
  }
  @reserved ~w(id inserted_at updated_at)

  @impl Mix.Task
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: [table: :string])

    case args do
      [domain, resource | fields] -> generate(domain, resource, fields, opts)
      _ -> Mix.raise("Usage: mix dandelion.gen.domain DOMAIN RESOURCE [field:type ...]")
    end
  end

  defp generate(domain, resource, field_args, opts) do
    for name <- [domain, resource] do
      unless name =~ ~r/\A[A-Z][A-Za-z0-9]*\z/,
        do: Mix.raise("#{inspect(name)} must be one CamelCase word, like Billing or Invoice")
    end

    fields = Enum.map(field_args, &parse_field!/1)

    if Enum.all?(fields, &(&1.type == "boolean")),
      do: Mix.raise("need at least one field that isn't a boolean, like number:string")

    if fields |> Enum.map(& &1.name) |> Enum.uniq() |> length() != length(fields),
      do: Mix.raise("a field is given twice")

    assigns = assigns(domain, resource, fields, opts[:table])
    files = files(assigns)

    taken = for {path, _} <- files, File.exists?(path), do: path

    if taken != [],
      do: Mix.raise("won't overwrite: " <> Enum.join(taken, ", ") <> " (already exist)")

    router = router!()

    for {path, contents} <- files do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
      Mix.shell().info([:green, "* creating ", :reset, path])
    end

    File.write!(router.path, router.insert.(routes(assigns)))
    Mix.shell().info([:green, "* updating ", :reset, router.path])

    Mix.Task.rerun("format", Enum.map(files, &elem(&1, 0)) ++ [router.path])

    Mix.shell().info("""

    #{assigns[:resource]} added to #{assigns[:domain]}. Next:

        mix ecto.migrate
        mix test
    """)
  end

  # -- what to write ------------------------------------------------------------

  defp assigns(domain, resource, fields, table) do
    snake = Macro.underscore(resource)
    table = table || pluralize(snake)

    [
      domain: domain,
      domain_dir: Macro.underscore(domain),
      resource: resource,
      snake: snake,
      plural: pluralize(snake),
      human: String.replace(snake, "_", " "),
      a_human: article(String.replace(snake, "_", " ")) <> " " <> String.replace(snake, "_", " "),
      a_human_lc:
        String.downcase(article(String.replace(snake, "_", " "))) <>
          " " <> String.replace(snake, "_", " "),
      table: table,
      migration_module: "Create" <> Macro.camelize(table),
      fields: fields,
      first: Enum.find(fields, &(&1.type != "boolean")),
      schema_fields: lines(fields, 4, &"field :#{&1.name}, :#{&1.ecto}#{&1.default}"),
      validations: lines(Enum.filter(fields, & &1.validation), 4, &"|> #{&1.validation}"),
      json_fields: lines(fields, 6, &"#{&1.name}: x.#{&1.name},"),
      columns: lines(fields, 6, &"add :#{&1.name}, :#{&1.column}, #{&1.column_opts}"),
      sample_params: lines(fields, 8, &~s("#{&1.name}" => #{&1.sample},))
    ]
  end

  # one line per item, the next ones indented `n` spaces, for the templates
  defp lines(items, n, fun) do
    items |> Enum.map(fun) |> Enum.join("\n" <> String.duplicate(" ", n))
  end

  defp article(word), do: if(String.starts_with?(word, ~w(a e i o u)), do: "An", else: "A")

  defp files(a) do
    d = a[:domain_dir]
    s = a[:snake]
    ts = migration_version()

    [
      {"lib/app/#{d}/models/#{s}.ex", render(:model, a)},
      {"lib/app/#{d}/repos/#{s}_repo.ex", render(:repo, a)},
      {"lib/app/#{d}/services/#{s}_service.ex", render(:service, a)},
      {"lib/app/#{d}/handlers/#{s}_handler.ex", render(:handler, a)},
      {"lib/app/#{d}/handlers/#{s}_json.ex", render(:json, a)},
      {"priv/repo/migrations/#{ts}_create_#{a[:table]}.exs", render(:migration, a)},
      {"test/app/#{d}/services/#{s}_service_test.exs", render(:service_test, a)},
      {"test/app/#{d}/handlers/#{s}_handler_test.exs", render(:handler_test, a)},
      {"test/support/app/#{d}/#{s}_fixtures.ex", render(:fixtures, a)}
    ]
  end

  # The migration's version is the time, to the second. Two resources made within
  # the same second would share one, and Ecto refuses duplicates: take the next
  # free second.
  defp migration_version(now \\ DateTime.utc_now()) do
    version = Calendar.strftime(now, "%Y%m%d%H%M%S")

    if Path.wildcard("priv/repo/migrations/#{version}_*") == [],
      do: version,
      else: migration_version(DateTime.add(now, 1, :second))
  end

  defp routes(a) do
    """

      # domain: #{a[:domain_dir]}
      scope "/api" do
        pipe_through :api

        post "/#{a[:plural]}", App.#{a[:domain]}.Handlers.#{a[:resource]}Handler, :create
        get "/#{a[:plural]}", App.#{a[:domain]}.Handlers.#{a[:resource]}Handler, :index
        get "/#{a[:plural]}/:id", App.#{a[:domain]}.Handlers.#{a[:resource]}Handler, :show
      end
    """
  end

  # The router's last `end` closes the module: the new scope goes before it.
  defp router! do
    path = "lib/platform/web/router.ex"

    unless File.exists?(path),
      do: Mix.raise("#{path} not found: run this from the root of a dandelion project")

    source = File.read!(path)

    unless source =~ ~r/\nend\s*\z/,
      do: Mix.raise("#{path} doesn't end the way the generator expects; add the routes by hand")

    insert = fn routes ->
      String.replace(source, ~r/\nend\s*\z/, "\n" <> String.trim_trailing(routes) <> "\nend\n")
    end

    %{path: path, insert: insert}
  end

  # -- fields ---------------------------------------------------------------------

  defp parse_field!(arg) do
    with [name, type] <- String.split(arg, ":"),
         true <- name =~ ~r/\A[a-z][a-z0-9_]*\z/,
         %{} = t <- @types[type] do
      if name in @reserved, do: Mix.raise("#{name} is added for you; leave it out")
      boolean? = type == "boolean"

      %{
        name: name,
        type: type,
        ecto: t.ecto,
        column: t.column,
        required: not boolean?,
        default: if(boolean?, do: ", default: false", else: ""),
        column_opts: if(boolean?, do: "null: false, default: false", else: "null: false"),
        validation: validation(name, type, t),
        sample: sample(name, type)
      }
    else
      _ ->
        Mix.raise(
          "#{inspect(arg)} isn't a field: write name:type, with a type from " <>
            Enum.join(Map.keys(@types) |> Enum.sort(), ", ")
        )
    end
  end

  defp validation(name, type, t) when type in ["string", "text"],
    do: "validate_length(:#{name}, max: #{t.max})"

  defp validation(name, "integer", _t),
    do:
      "validate_number(:#{name}, greater_than_or_equal_to: -1_000_000_000_000, less_than_or_equal_to: 1_000_000_000_000)"

  defp validation(_name, "boolean", _t), do: nil

  defp sample(name, type) when type in ["string", "text"], do: inspect("#{name} 1")
  defp sample(_name, "integer"), do: "1"
  defp sample(_name, "boolean"), do: "true"

  defp pluralize(word) do
    cond do
      String.ends_with?(word, ["s", "x", "z", "ch", "sh"]) -> word <> "es"
      Regex.match?(~r/[^aeiou]y\z/, word) -> String.slice(word, 0..-2//1) <> "ies"
      true -> word <> "s"
    end
  end

  # -- templates ------------------------------------------------------------------

  defp render(name, assigns), do: EEx.eval_string(template(name), assigns: assigns, trim: true)

  defp template(:model) do
    ~S'''
    defmodule App.<%= @domain %>.Models.<%= @resource %> do
      @moduledoc """
      <%= @a_human %>. ≈ `type <%= @resource %> struct` in `model/<%= @snake %>.go`, plus its
      validation: `create_changeset/2` checks new input before anything touches
      the database.
      """
      use Ecto.Schema
      import Ecto.Changeset

      @timestamps_opts [type: :utc_datetime_usec]
      schema "<%= @table %>" do
        <%= @schema_fields %>
        timestamps()
      end

      @type t :: %__MODULE__{}

      @fields ~w(<%= Enum.map_join(@fields, " ", & &1.name) %>)a
      @required ~w(<%= @fields |> Enum.filter(& &1.required) |> Enum.map_join(" ", & &1.name) %>)a

      @doc "Validates a new <%= @human %>. Errors come back as a changeset."
      def create_changeset(<%= @snake %> \\ %__MODULE__{}, attrs) do
        <%= @snake %>
        |> cast(attrs, @fields)
        |> validate_required(@required)
        <%= @validations %>
      end
    end
    '''
  end

  defp template(:repo) do
    ~S'''
    defmodule Platform.Database.Repos.<%= @resource %>Repo do
      @moduledoc """
      <%= @resource %> queries — and nothing else. ≈ `repo/<%= @plural %>.go`.

      No business rules here: the service decides *what* happens, the repo only
      knows *how* to read and write it.
      """
      import Ecto.Query

      alias App.<%= @domain %>.Models.<%= @resource %>
      alias Platform.Database.Repo

      @doc "<%= @a_human %>, or nil."
      @spec get(integer()) :: <%= @resource %>.t() | nil
      def get(id), do: Repo.get(<%= @resource %>, id)

      @doc "<%= String.capitalize(@plural) %> newest first, one page at a time."
      @spec list(%{page: pos_integer(), per_page: pos_integer()}) :: [<%= @resource %>.t()]
      def list(%{page: page, per_page: per_page}) do
        <%= @resource %>
        |> order_by(desc: :inserted_at, desc: :id)
        |> limit(^per_page)
        |> offset(^((page - 1) * per_page))
        |> Repo.all()
      end

      @doc "Inserts a new <%= @human %> from a changeset."
      def insert(%Ecto.Changeset{} = changeset), do: Repo.insert(changeset)
    end
    '''
  end

  defp template(:service) do
    ~S'''
    defmodule App.<%= @domain %>.Services.<%= @resource %>Service do
      @moduledoc """
      <%= @resource %> business rules. ≈ `service/<%= @plural %>.go`.

      No HTTP here (handlers do that) and no SQL (repos do that). Every function
      returns `{:ok, value}` or `{:error, reason}` — Elixir's `(value, err)`.
      """
      alias App.<%= @domain %>.Models.<%= @resource %>
      alias Platform.Database.Repos.<%= @resource %>Repo

      @type error :: :not_found | {:invalid, String.t()} | Ecto.Changeset.t()

      @max_per_page 100
      # keeps OFFSET well inside Postgres's bigint
      @max_page 1_000_000

      @doc "Creates <%= @a_human_lc %>. Validation errors come back as a changeset."
      @spec create(map()) :: {:ok, <%= @resource %>.t()} | {:error, error()}
      def create(params), do: params |> <%= @resource %>.create_changeset() |> <%= @resource %>Repo.insert()

      @doc "One <%= @human %>."
      @spec get(integer()) :: {:ok, <%= @resource %>.t()} | {:error, error()}
      def get(id) do
        case <%= @resource %>Repo.get(id) do
          nil -> {:error, :not_found}
          <%= @snake %> -> {:ok, <%= @snake %>}
        end
      end

      @doc """
      <%= String.capitalize(@plural) %>, newest first. `params`: optional `"page"` (from 1),
      `"per_page"` (1..#{@max_per_page}, default 20).
      """
      @spec list(map()) ::
              {:ok, %{<%= @plural %>: [<%= @resource %>.t()], page: pos_integer(), per_page: pos_integer()}}
              | {:error, error()}
      def list(params) do
        with {:ok, page} <- positive_int(params["page"], 1, @max_page, "page"),
             {:ok, per_page} <- positive_int(params["per_page"], 20, @max_per_page, "per_page") do
          {:ok,
           %{
             <%= @plural %>: <%= @resource %>Repo.list(%{page: page, per_page: per_page}),
             page: page,
             per_page: per_page
           }}
        end
      end

      defp positive_int(nil, default, _max, _name), do: {:ok, default}

      # Query parameters are strings — or maps / lists (`?page[x]=1`), which are
      # just as invalid.
      defp positive_int(value, _default, max, name) do
        case is_binary(value) and Integer.parse(value) do
          {n, ""} when n in 1..max//1 -> {:ok, n}
          _ -> {:error, {:invalid, "#{name} must be a whole number from 1 to #{max}"}}
        end
      end
    end
    '''
  end

  defp template(:handler) do
    ~S'''
    defmodule App.<%= @domain %>.Handlers.<%= @resource %>Handler do
      @moduledoc """
      HTTP handlers for <%= @plural %>. ≈ `http/<%= @plural %>.go`: read the request, call the
      service, write JSON. Errors go to `Platform.Web.FallbackHandler`
      (`action_fallback`), so each action only handles the happy path.
      """
      use Platform.Web, :handler

      alias App.<%= @domain %>.Handlers.<%= @resource %>JSON
      alias App.<%= @domain %>.Services.<%= @resource %>Service

      action_fallback Platform.Web.FallbackHandler

      # POST /api/<%= @plural %>
      def create(conn, params) do
        with {:ok, <%= @snake %>} <- <%= @resource %>Service.create(params) do
          conn |> put_status(:created) |> json(<%= @resource %>JSON.<%= @snake %>(<%= @snake %>))
        end
      end

      # GET /api/<%= @plural %>/:id
      def show(conn, %{"id" => id}) do
        with {:ok, id} <- id(id),
             {:ok, <%= @snake %>} <- <%= @resource %>Service.get(id) do
          json(conn, <%= @resource %>JSON.<%= @snake %>(<%= @snake %>))
        end
      end

      # GET /api/<%= @plural %>?page=1&per_page=20
      def index(conn, params) do
        with {:ok, page} <- <%= @resource %>Service.list(params) do
          json(conn, <%= @resource %>JSON.page(page))
        end
      end

      # Path ids are strings; anything that isn't a positive bigint is 404.
      defp id(value) do
        case Integer.parse(value) do
          {id, ""} when id in 1..9_223_372_036_854_775_807//1 -> {:ok, id}
          _ -> {:error, :not_found}
        end
      end
    end
    '''
  end

  defp template(:json) do
    ~S'''
    defmodule App.<%= @domain %>.Handlers.<%= @resource %>JSON do
      @moduledoc """
      The JSON shape of <%= @plural %>. ≈ a Go response struct with `json:"…"` tags:
      what the API promises, independent of the database columns.
      """
      alias App.<%= @domain %>.Models.<%= @resource %>

      def <%= @snake %>(%<%= @resource %>{} = x) do
        %{
          id: x.id,
          <%= @json_fields %>
          created_at: x.inserted_at,
          updated_at: x.updated_at
        }
      end

      def page(%{<%= @plural %>: <%= @plural %>, page: page, per_page: per_page}) do
        %{<%= @plural %>: Enum.map(<%= @plural %>, &<%= @snake %>/1), page: page, per_page: per_page}
      end
    end
    '''
  end

  defp template(:migration) do
    ~S'''
    defmodule Platform.Database.Repo.Migrations.<%= @migration_module %> do
      use Ecto.Migration

      def change do
        create table(:<%= @table %>) do
          <%= @columns %>
          timestamps(type: :utc_datetime_usec)
        end
      end
    end
    '''
  end

  defp template(:fixtures) do
    ~S'''
    defmodule App.<%= @domain %>.<%= @resource %>Fixtures do
      @moduledoc "Test helpers that create <%= @plural %>. ≈ a Go `newTest<%= @resource %>(t)` helper."
      alias App.<%= @domain %>.Services.<%= @resource %>Service

      @doc "Valid params for a new <%= @human %>, with any of them overridden."
      def <%= @snake %>_params(overrides \\ %{}) do
        Map.merge(
          %{
            <%= @sample_params %>
          },
          overrides
        )
      end

      @doc "<%= @a_human %> in the database."
      def <%= @snake %>_fixture(overrides \\ %{}) do
        {:ok, <%= @snake %>} = <%= @resource %>Service.create(<%= @snake %>_params(overrides))
        <%= @snake %>
      end
    end
    '''
  end

  defp template(:service_test) do
    ~S'''
    defmodule App.<%= @domain %>.Services.<%= @resource %>ServiceTest do
      use Platform.DataCase, async: true

      import App.<%= @domain %>.<%= @resource %>Fixtures

      alias App.<%= @domain %>.Services.<%= @resource %>Service

      describe "create/1" do
        test "creates the <%= @human %>" do
          assert {:ok, <%= @snake %>} = <%= @resource %>Service.create(<%= @snake %>_params())
          assert <%= @snake %>.id
        end

        test "<%= @first.name %> is required" do
          assert {:error, changeset} =
                   <%= @resource %>Service.create(Map.delete(<%= @snake %>_params(), "<%= @first.name %>"))

          assert %{<%= @first.name %>: ["can't be blank"]} =
                   Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
        end
      end

      describe "get/1" do
        test "finds <%= @a_human_lc %>, or :not_found" do
          <%= @snake %> = <%= @snake %>_fixture()
          assert {:ok, %{id: id}} = <%= @resource %>Service.get(<%= @snake %>.id)
          assert id == <%= @snake %>.id
          assert <%= @resource %>Service.get(-1) == {:error, :not_found}
        end
      end

      describe "list/1" do
        test "pages, newest first" do
          old = <%= @snake %>_fixture()
          new = <%= @snake %>_fixture()

          assert {:ok, %{<%= @plural %>: [first | _], page: 1, per_page: 20}} = <%= @resource %>Service.list(%{})
          assert first.id == new.id

          assert {:ok, %{<%= @plural %>: [only], per_page: 1}} = <%= @resource %>Service.list(%{"per_page" => "1"})
          assert only.id == new.id

          assert {:ok, %{<%= @plural %>: [second]}} =
                   <%= @resource %>Service.list(%{"per_page" => "1", "page" => "2"})

          assert second.id == old.id
        end

        test "bad parameters are errors, not crashes" do
          assert {:error, {:invalid, _}} = <%= @resource %>Service.list(%{"page" => "0"})
          assert {:error, {:invalid, _}} = <%= @resource %>Service.list(%{"per_page" => "101"})
          assert {:error, {:invalid, _}} = <%= @resource %>Service.list(%{"page" => %{"x" => "1"}})
        end
      end
    end
    '''
  end

  defp template(:handler_test) do
    ~S'''
    defmodule App.<%= @domain %>.Handlers.<%= @resource %>HandlerTest do
      use Platform.ConnCase, async: true

      import App.<%= @domain %>.<%= @resource %>Fixtures

      test "POST /api/<%= @plural %> creates <%= @a_human_lc %>", %{conn: conn} do
        conn = post(conn, "/api/<%= @plural %>", <%= @snake %>_params())
        assert %{"id" => _, "created_at" => _} = json_response(conn, 201)
      end

      test "POST /api/<%= @plural %> with invalid input is 422 with field errors", %{conn: conn} do
        params = Map.delete(<%= @snake %>_params(), "<%= @first.name %>")
        conn = post(conn, "/api/<%= @plural %>", params)

        assert %{"errors" => %{"<%= @first.name %>" => ["can't be blank"]}} = json_response(conn, 422)
      end

      test "GET /api/<%= @plural %>/:id, and 404 for unknown or malformed ids", %{conn: conn} do
        <%= @snake %> = <%= @snake %>_fixture()
        assert %{"id" => id} = conn |> get("/api/<%= @plural %>/#{<%= @snake %>.id}") |> json_response(200)
        assert id == <%= @snake %>.id

        assert %{"error" => "not found"} = conn |> get("/api/<%= @plural %>/999999") |> json_response(404)
        assert %{"error" => "not found"} = conn |> get("/api/<%= @plural %>/abc") |> json_response(404)
      end

      test "GET /api/<%= @plural %> pages; bad parameters are 400", %{conn: conn} do
        <%= @snake %>_fixture()

        assert %{"<%= @plural %>" => [_ | _], "page" => 1, "per_page" => 20} =
                 conn |> get("/api/<%= @plural %>") |> json_response(200)

        assert %{"error" => _} = conn |> get("/api/<%= @plural %>?page=0") |> json_response(400)
      end
    end
    '''
  end
end
