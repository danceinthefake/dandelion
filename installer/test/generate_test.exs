defmodule DandelionNew.GenerateTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Dandelion.New

  defp files(app, module, example? \\ true), do: Map.new(New.generate(app, module, example?))

  defp secrets(files) do
    files
    |> Map.values()
    |> Enum.flat_map(
      &Regex.scan(~r/(?:secret_key_base|signing_salt): "([^"]+)"/, &1, capture: :all_but_first)
    )
    |> List.flatten()
  end

  test "renames the app everywhere: paths and contents" do
    files = files("my_app", "MyApp")

    assert Map.has_key?(files, "lib/my_app/services/order_service.ex")
    assert Map.has_key?(files, "lib/my_app_web/handlers/order_handler.ex")

    assert files["lib/my_app/services/order_service.ex"] =~
             "defmodule MyApp.Services.OrderService"

    assert files["config/dev.exs"] =~ "database: \"my_app_dev\""
    assert files["compose.yaml"] =~ "container_name: my_app-pg"

    for {path, contents} <- files do
      refute path =~ ~r/shop/i, path
      refute contents =~ ~r/\bShop\b|shop_|Shop\.|ShopWeb/, "#{path} still mentions shop"
    end
  end

  test "names containing 'shop' are renamed once, not twice" do
    workshop = files("workshop", "Workshop")
    assert workshop["lib/workshop/repo.ex"] =~ "defmodule Workshop.Repo do"
    assert workshop["mix.exs"] =~ "app: :workshop,"

    admin = files("shop_admin", "ShopAdmin")
    assert Map.has_key?(admin, "lib/shop_admin_web/router.ex")
    assert admin["lib/shop_admin_web/router.ex"] =~ "defmodule ShopAdminWeb.Router do"
  end

  test "every project gets its own secrets, never the example's" do
    example = secrets(Map.new(DandelionNew.Templates.all()))
    a = secrets(files("a_app", "AApp"))
    b = secrets(files("b_app", "BApp"))

    assert length(a) == 4
    assert MapSet.disjoint?(MapSet.new(a), MapSet.new(example))
    assert MapSet.disjoint?(MapSet.new(a), MapSet.new(b))

    assert Enum.all?(
             Enum.zip(Enum.sort_by(a, &byte_size/1), Enum.sort_by(example, &byte_size/1)),
             fn {x, y} -> byte_size(x) == byte_size(y) end
           )
  end

  test "--no-example keeps the layout and drops the orders example" do
    files = files("my_app", "MyApp", false)

    refute Enum.any?(Map.keys(files), &(&1 =~ "order"))
    assert Map.has_key?(files, "lib/my_app/services/.gitkeep")
    assert Map.has_key?(files, "lib/my_app_web/handlers/fallback_handler.ex")
    refute files["lib/my_app_web/router.ex"] =~ "/orders"
    refute files["lib/my_app/application.ex"] =~ "ExpireUnpaidOrders"
    refute files["config/runtime.exs"] =~ "ExpireUnpaidOrders"
    refute files["README.md"] =~ "orders"
  end

  describe "mix dandelion.new" do
    @tag :tmp_dir
    test "writes the project and makes the release scripts executable", %{tmp_dir: dir} do
      path = Path.join(dir, "my_app")
      Mix.shell(Mix.Shell.Process)
      New.run([path])

      assert File.read!(Path.join(path, "mix.exs")) =~ "app: :my_app,"

      assert File.stat!(Path.join(path, "rel/overlays/bin/migrate")).mode |> Bitwise.band(0o111) !=
               0

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
