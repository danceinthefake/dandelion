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

      compose = ["compose", "-f", "deploy/compose.cluster.yaml"]
      on_exit(fn -> System.cmd("docker", compose ++ ["down", "-v"], cd: path) end)

      cmd!(path, "docker", compose ++ ["up", "-d", "--build"])
      Process.sleep(30_000)
      out = cmd!(path, Path.join(path, "deploy/cluster-proof.sh"), [])
      assert out =~ "all good"
    end
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
