defmodule DandelionNew.IntegrationTest do
  # Generates real projects and runs their own checks. Slow; needs network
  # and Postgres on :55432 (docker compose up -d in ../example).
  #   mix test --include integration
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 600_000
  @moduletag :tmp_dir

  for {name, flags} <- [
        {"with the example", []},
        {"without the frontend", ["--no-frontend"]},
        {"without the example", ["--no-example"]}
      ] do
    test "a generated project compiles cleanly, passes its tests and credo (#{name})", %{
      tmp_dir: dir
    } do
      app = "gen_#{System.unique_integer([:positive])}"
      path = Path.join(dir, app)
      Mix.shell(Mix.Shell.Quiet)
      Mix.Tasks.Dandelion.New.run([path | unquote(flags)])
      use_local_dandelion(path)

      mix!(path, ["deps.get"])
      mix!(path, ["compile", "--warnings-as-errors"])
      mix!(path, ["format", "--check-formatted"])
      mix!(path, ["test"], %{"MIX_ENV" => "test"})
      mix!(path, ["credo", "--strict"])
      mix!(path, ["ecto.drop"], %{"MIX_ENV" => "test"})
    end
  end

  test "the generated frontend builds", %{tmp_dir: dir} do
    path = Path.join(dir, "gen_ui")
    Mix.shell(Mix.Shell.Quiet)
    Mix.Tasks.Dandelion.New.run([path])
    use_local_dandelion(path)

    assets = Path.join(path, "assets")
    cmd!(assets, "npm", ["ci"])
    cmd!(assets, "npm", ["run", "build"])
    assert File.exists?(Path.join(path, "priv/static/app/index.html"))
  end

  # The generated project's own cluster proof, on three containers. Needs
  # Docker and free ports 8080 (nginx).
  for {name, flags} <- [{"with everything", []}, {"without the example", ["--no-example"]}] do
    test "a generated project's cluster proof passes (#{name})", %{tmp_dir: dir} do
      path = Path.join(dir, "gen_cluster")
      Mix.shell(Mix.Shell.Quiet)
      Mix.Tasks.Dandelion.New.run([path | unquote(flags)])
      use_local_dandelion(path)

      compose = ["compose", "-f", "deploy/compose.cluster.yaml"]
      on_exit(fn -> System.cmd("docker", compose ++ ["down", "-v"], cd: path) end)

      cmd!(path, "docker", compose ++ ["up", "-d", "--build"])
      Process.sleep(30_000)
      out = cmd!(path, Path.join(path, "deploy/cluster-proof.sh"), [])
      assert out =~ "all good"
    end
  end

  # A generated project takes dandelion from hex. By default the tests point it
  # at the library in this repo instead (testing a change before it is
  # released); DANDELION_FROM_HEX=1 leaves the published dependency alone.
  # The Docker build gets the same copy: vendor/dandelion.
  @library Path.expand("../..", __DIR__)
  defp use_local_dandelion(path) do
    if System.get_env("DANDELION_FROM_HEX"), do: :ok, else: vendor_local_dandelion(path)
  end

  defp vendor_local_dandelion(path) do
    vendor = Path.join(path, "vendor/dandelion")
    File.mkdir_p!(vendor)
    File.cp!(Path.join(@library, "mix.exs"), Path.join(vendor, "mix.exs"))
    File.cp_r!(Path.join(@library, "lib"), Path.join(vendor, "lib"))

    edit!(path, "mix.exs", ~s({:dandelion, "~> 0.1"}), ~s({:dandelion, path: "vendor/dandelion"}))

    edit!(
      path,
      "Dockerfile",
      "COPY mix.exs mix.lock ./",
      "COPY vendor/dandelion vendor/dandelion\nCOPY mix.exs mix.lock ./"
    )
  end

  defp edit!(path, file, from, to) do
    file = Path.join(path, file)
    contents = File.read!(file)
    assert contents =~ from, "#{file} has no #{inspect(from)}"
    File.write!(file, String.replace(contents, from, to))
  end

  defp cmd!(path, cmd, args) do
    {out, status} = System.cmd(cmd, args, cd: path, stderr_to_stdout: true)
    assert status == 0, "#{cmd} #{Enum.join(args, " ")} failed:\n#{out}"
    out
  end

  defp mix!(path, args, env \\ %{}) do
    {out, status} =
      System.cmd("mix", args, cd: path, env: Map.to_list(env), stderr_to_stdout: true)

    assert status == 0, "mix #{Enum.join(args, " ")} failed:\n#{out}"
    out
  end
end
