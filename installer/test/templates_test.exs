defmodule DandelionNew.TemplatesTest do
  use ExUnit.Case, async: true

  alias DandelionNew.Templates

  test "templates are exactly ../example (run `mix dandelion.sync_templates` after changing it)" do
    templates = Map.new(Templates.all())
    example = Templates.example_files()

    assert Enum.sort(Map.keys(templates)) == Enum.sort(example)

    for file <- example do
      assert templates[file] == File.read!(Path.join(Templates.example_dir(), file)),
             "#{file} differs"
    end
  end
end
