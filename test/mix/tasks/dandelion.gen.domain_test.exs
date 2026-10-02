defmodule Mix.Tasks.Dandelion.Gen.DomainTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Dandelion.Gen.Domain

  @moduletag :tmp_dir

  @router """
  defmodule Platform.Web.Router do
    use Platform.Web, :router

    scope "/api" do
      pipe_through :api
    end
  end
  """

  # what a real project's formatter (import_deps: [:ecto, :phoenix]) leaves paren-less
  @formatter """
  [
    inputs: ["{lib,test,priv}/**/*.{ex,exs}"],
    locals_without_parens: [field: 2, field: 3, add: 3, create: 1, post: 3, get: 3, pipe_through: 1, scope: 2]
  ]
  """

  # runs the task inside a fresh "project" that only has a router
  defp gen(dir, args) do
    File.write!(Path.join(dir, ".formatter.exs"), @formatter)
    File.mkdir_p!(Path.join(dir, "lib/platform/web"))
    router = Path.join(dir, "lib/platform/web/router.ex")
    unless File.exists?(router), do: File.write!(router, @router)
    Mix.shell(Mix.Shell.Process)
    File.cd!(dir, fn -> Domain.run(args) end)
  end

  defp read(dir, path), do: File.read!(Path.join(dir, path))
  defp exists?(dir, path), do: File.exists?(Path.join(dir, path))

  test "writes every layer, a migration and the tests", %{tmp_dir: dir} do
    gen(dir, ~w(Billing Invoice number:string amount_cents:integer paid:boolean))

    for path <- ~w(
          lib/app/billing/models/invoice.ex
          lib/app/billing/repos/invoice_repo.ex
          lib/app/billing/services/invoice_service.ex
          lib/app/billing/handlers/invoice_handler.ex
          lib/app/billing/handlers/invoice_json.ex
          test/app/billing/services/invoice_service_test.exs
          test/app/billing/handlers/invoice_handler_test.exs
          test/support/app/billing/invoice_fixtures.ex
        ),
        do: assert(exists?(dir, path), path)

    assert [migration] =
             Path.wildcard(Path.join(dir, "priv/repo/migrations/*_create_invoices.exs"))

    assert File.read!(migration) =~ "defmodule Platform.Database.Repo.Migrations.CreateInvoices"
  end

  test "fields: types, required, booleans default to false", %{tmp_dir: dir} do
    gen(dir, ~w(Billing Invoice number:string notes:text amount_cents:integer paid:boolean))

    model = read(dir, "lib/app/billing/models/invoice.ex")
    assert model =~ "defmodule App.Billing.Models.Invoice do"
    assert model =~ "field :number, :string"
    assert model =~ "field :amount_cents, :integer"
    assert model =~ "field :paid, :boolean, default: false"
    assert model =~ "@required ~w(number notes amount_cents)a"
    assert model =~ "validate_length(:number, max: 255)"
    assert model =~ "validate_length(:notes, max: 10_000)"

    [migration] = Path.wildcard(Path.join(dir, "priv/repo/migrations/*_create_invoices.exs"))
    migration = File.read!(migration)
    assert migration =~ "add :amount_cents, :bigint, null: false"
    assert migration =~ "add :paid, :boolean, null: false, default: false"
  end

  test "the router gets the three routes, once per resource", %{tmp_dir: dir} do
    gen(dir, ~w(Billing Invoice number:string))
    gen(dir, ~w(Billing Payment reference:string))

    router = read(dir, "lib/platform/web/router.ex")
    assert router =~ ~s(post "/invoices", App.Billing.Handlers.InvoiceHandler, :create)
    assert router =~ ~s(get "/invoices/:id", App.Billing.Handlers.InvoiceHandler, :show)
    assert router =~ ~s(get "/payments", App.Billing.Handlers.PaymentHandler, :index)
    # the original scope is still there, and the module still ends once
    assert router =~ "pipe_through :api"
    assert Regex.scan(~r/\nend\s*\z/, router) |> length() == 1
  end

  test "behind the login when the router has an :authenticated pipeline", %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "lib/platform/web"))

    File.write!(Path.join(dir, "lib/platform/web/router.ex"), """
    defmodule Platform.Web.Router do
      use Platform.Web, :router

      pipeline :authenticated do
        plug :some_login
      end
    end
    """)

    gen(dir, ~w(Billing Invoice number:string))
    router = read(dir, "lib/platform/web/router.ex")
    assert router =~ "pipe_through [:api, :authenticated]"
    assert router =~ ~s(post "/invoices", App.Billing.Handlers.InvoiceHandler, :create)
  end

  @guarded_router """
  defmodule Platform.Web.Router do
    use Platform.Web, :router

    pipeline :authenticated do
      plug :some_login
    end
  end
  """

  defp project(dir, router, login_helper?) do
    File.mkdir_p!(Path.join(dir, "lib/platform/web"))
    File.write!(Path.join(dir, "lib/platform/web/router.ex"), router)

    if login_helper? do
      File.mkdir_p!(Path.join(dir, "test/support/app/accounts"))

      File.write!(
        Path.join(dir, "test/support/app/accounts/fixtures.ex"),
        "defmodule App.Accounts.Fixtures do\n  def log_in(conn, _user), do: conn\nend\n"
      )
    end
  end

  test "a login in the project: the handler tests log in", %{tmp_dir: dir} do
    project(dir, @guarded_router, true)
    gen(dir, ~w(Billing Invoice number:string))

    test = read(dir, "test/app/billing/handlers/invoice_handler_test.exs")
    assert test =~ "import App.Accounts.Fixtures"
    assert test =~ "log_in(conn, user_fixture())"
    assert test =~ ~s(test "POST /api/invoices creates an invoice")
  end

  test "a login the task doesn't know: guarded routes, tests that only expect a 401", %{
    tmp_dir: dir
  } do
    project(dir, @guarded_router, false)
    gen(dir, ~w(Billing Invoice number:string))

    assert read(dir, "lib/platform/web/router.ex") =~ "pipe_through [:api, :authenticated]"
    test = read(dir, "test/app/billing/handlers/invoice_handler_test.exs")
    assert test =~ ~s(test "the routes need a login")
    refute test =~ "creates an invoice"
  end

  test "no login at all: open routes, full handler tests", %{tmp_dir: dir} do
    gen(dir, ~w(Billing Invoice number:string))
    test = read(dir, "test/app/billing/handlers/invoice_handler_test.exs")
    refute test =~ "log_in"
    assert test =~ ~s(test "POST /api/invoices creates an invoice")
  end

  test "without one, the routes use :api only", %{tmp_dir: dir} do
    gen(dir, ~w(Billing Invoice number:string))
    router = read(dir, "lib/platform/web/router.ex")
    assert router =~ "# domain: billing\n  scope \"/api\" do\n    pipe_through :api\n"
    refute router =~ ":authenticated"
  end

  test "plurals: category → categories, box → boxes, --table overrides", %{tmp_dir: dir} do
    gen(dir, ~w(Shop Category name:string))
    assert [_] = Path.wildcard(Path.join(dir, "priv/repo/migrations/*_create_categories.exs"))
    assert read(dir, "lib/platform/web/router.ex") =~ ~s(post "/categories")

    gen(dir, ~w(Shop Box label:string))
    assert [_] = Path.wildcard(Path.join(dir, "priv/repo/migrations/*_create_boxes.exs"))

    gen(dir, ~w(Shop Gadget name:string --table widgets))
    assert [_] = Path.wildcard(Path.join(dir, "priv/repo/migrations/*_create_widgets.exs"))
    assert read(dir, "lib/app/shop/models/gadget.ex") =~ ~s(schema "widgets")
  end

  test "resources made within the same second get different migration versions", %{tmp_dir: dir} do
    for resource <- ~w(Invoice Payment Refund Credit Debit),
        do: gen(dir, ["Billing", resource, "name:string"])

    versions =
      dir
      |> Path.join("priv/repo/migrations/*.exs")
      |> Path.wildcard()
      |> Enum.map(&(&1 |> Path.basename() |> String.split("_", parts: 2) |> hd()))

    assert length(versions) == 5
    assert length(Enum.uniq(versions)) == 5
  end

  test "an underscored name: InvoiceItem → invoice_items", %{tmp_dir: dir} do
    gen(dir, ~w(Billing InvoiceItem sku:string))
    assert exists?(dir, "lib/app/billing/models/invoice_item.ex")
    assert read(dir, "lib/app/billing/models/invoice_item.ex") =~ ~s(schema "invoice_items")
  end

  test "refuses to overwrite, and changes nothing when it does", %{tmp_dir: dir} do
    gen(dir, ~w(Billing Invoice number:string))
    router = read(dir, "lib/platform/web/router.ex")

    assert_raise Mix.Error, ~r/won't overwrite.*invoice\.ex/, fn ->
      gen(dir, ~w(Billing Invoice number:string))
    end

    assert read(dir, "lib/platform/web/router.ex") == router
  end

  test "refuses bad input with a message that says what to write", %{tmp_dir: dir} do
    bad = [
      {~w(billing Invoice number:string), ~r/CamelCase/},
      {~w(Billing invoice number:string), ~r/CamelCase/},
      {~w(Billing Invoice number), ~r/isn't a field/},
      {~w(Billing Invoice number:varchar), ~r/isn't a field.*boolean, integer, string, text/},
      {~w(Billing Invoice Number:string), ~r/isn't a field/},
      {~w(Billing Invoice id:integer), ~r/added for you/},
      {~w(Billing Invoice paid:boolean), ~r/at least one field that isn't a boolean/},
      {~w(Billing Invoice a:string a:integer), ~r/given twice/},
      {~w(Billing), ~r/Usage/}
    ]

    for {args, message} <- bad do
      assert_raise Mix.Error, message, fn -> gen(dir, args) end
    end

    refute exists?(dir, "lib/app")
  end

  test "outside a dandelion project it says so", %{tmp_dir: dir} do
    Mix.shell(Mix.Shell.Process)

    assert_raise Mix.Error, ~r/not found: run this from the root/, fn ->
      File.cd!(dir, fn -> Domain.run(~w(Billing Invoice number:string)) end)
    end
  end
end
