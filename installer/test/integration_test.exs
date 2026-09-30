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

  defp mix!(path, args, env \\ %{}) do
    {out, status} =
      System.cmd("mix", args, cd: path, env: Map.to_list(env), stderr_to_stdout: true)

    assert status == 0, "mix #{Enum.join(args, " ")} failed:\n#{out}"
    out
  end
end
