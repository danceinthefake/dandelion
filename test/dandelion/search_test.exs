defmodule Dandelion.SearchTest do
  use Dandelion.DataCase, async: true

  alias Dandelion.Search
  alias Dandelion.TestRepo

  defp item(title, body \\ nil) do
    %{rows: [[id]]} =
      TestRepo.query!("INSERT INTO search_items (title, body) VALUES ($1, $2) RETURNING id", [
        title,
        body
      ])

    id
  end

  defp find(text, opts \\ []) do
    Search.search(
      TestRepo,
      "search_items",
      text,
      Keyword.merge([select: ["id", "title"], snippet: "body", fuzzy: "title"], opts)
    )
  end

  defp titles(result), do: Enum.map(result.rows, & &1["title"])

  describe "tsquery/1" do
    test "keeps words only: every one a prefix, all required" do
      assert Search.tsquery("Gre tea") == "gre:* & tea:*"
      assert Search.tsquery("  café   au lait ") == "café:* & au:* & lait:*"
      assert Search.tsquery("2024 edition") == "2024:* & edition:*"
    end

    test "operators and quotes cannot get through" do
      assert Search.tsquery("a & b | !c (d) e:* 'f' \"g\" h\\ <-> i") ==
               "a:* & b:* & c:* & d:* & e:* & f:* & g:* & h:* & i:*"

      assert Search.tsquery("'; DROP TABLE x; --") == "drop:* & table:* & x:*"
    end

    test "nothing to search for is nil" do
      assert Search.tsquery("") == nil
      assert Search.tsquery("  ! ? & ") == nil
    end

    test "is bounded: ten words, fifty characters each" do
      query = Search.tsquery(Enum.map_join(1..20, " ", &"w#{&1}"))
      assert length(String.split(query, " & ")) == 10
      assert Search.tsquery(String.duplicate("a", 200)) == String.duplicate("a", 50) <> ":*"
    end
  end

  describe "search/4" do
    test "finds a word, as a prefix, and requires every word" do
      green = item("Green tea", "Fresh leaves from the hills")
      _black = item("Black tea", "Strong and dark")
      _cup = item("Tea cup", "Holds green tea or anything")

      assert [green] ==
               find("gre")
               |> Map.fetch!(:rows)
               |> Enum.map(& &1["id"])
               |> Enum.filter(&(&1 == green))

      assert Enum.sort(titles(find("tea"))) == ["Black tea", "Green tea", "Tea cup"]
      assert Enum.sort(titles(find("green tea"))) == ["Green tea", "Tea cup"]
      assert titles(find("black green", fallback: false)) == []
    end

    test "a match in the title outranks one in the body" do
      body_only = item("Cup", "Made for green tea")
      title = item("Green tea", "Leaves")

      assert [^title, ^body_only] =
               find("green")
               |> Map.fetch!(:rows)
               |> Enum.map(& &1["id"])
               |> Enum.filter(&(&1 in [title, body_only]))

      [first, second | _] = find("green").rows
      assert first["rank"] > second["rank"]
    end

    test "accents and case do not matter, either way" do
      id = item("Café Crème")
      other = item("Plain cafe")

      ids = fn q -> find(q).rows |> Enum.map(& &1["id"]) end
      assert id in ids.("cafe") and id in ids.("CAFÉ") and id in ids.("creme")
      assert other in ids.("café")
    end

    test "a snippet marks the words, and is plain text" do
      id =
        item(
          "Tea",
          "<script>alert(1)</script> Our green tea is picked by hand in the early morning hills"
        )

      row = find("green").rows |> Enum.find(&(&1["id"] == id))
      assert row["snippet"] =~ "[[green]]"
      # not HTML: the stored text is passed through as it is, for the client to escape
      assert row["snippet"] =~ "<script>" or not (row["snippet"] =~ "<mark>")
    end

    test "a typo falls back to similar words, and says so" do
      id = item("Green tea")
      result = find("grean tea")
      assert result.match == :fuzzy
      assert id in Enum.map(result.rows, & &1["id"])
      assert Enum.all?(result.rows, &(&1["rank"] > 0))
    end

    test "a query that finds something never mixes in guesses" do
      item("Green tea")
      item("Greene gardens")
      result = find("green")
      assert result.match == :text
      assert "Green tea" in titles(result)
    end

    test "the fallback can be turned off, and does not apply to later pages" do
      item("Green tea")
      assert find("grean", fallback: false) == %{total: 0, match: :none, rows: []}
      assert find("grean", offset: 5).rows == []
    end

    test "nothing found, and nothing to search for" do
      assert find("zzzzqqq") == %{total: 0, match: :none, rows: []}
      assert find("") == %{total: 0, match: :none, rows: []}
      assert find("!!!") == %{total: 0, match: :none, rows: []}
    end

    test "total counts every match, whatever the page" do
      tag = "qq#{System.unique_integer([:positive])}"
      for i <- 1..7, do: item("#{tag} item #{i}")

      page = find(tag, limit: 3)
      assert page.total == 7 and length(page.rows) == 3
      page2 = find(tag, limit: 3, offset: 3)
      assert page2.total == 7 and length(page2.rows) == 3

      assert MapSet.disjoint?(
               MapSet.new(page.rows, & &1["id"]),
               MapSet.new(page2.rows, & &1["id"])
             )

      assert length(find(tag, limit: 3, offset: 6).rows) == 1
    end

    test "limit and offset are bounded" do
      tag = "bb#{System.unique_integer([:positive])}"
      for i <- 1..60, do: item("#{tag} #{i}")
      assert length(find(tag, limit: 10_000).rows) == 50
      assert length(find(tag, limit: 0).rows) == 1
      assert find(tag, offset: 100_000).rows == []
    end

    test "any text the user can type is fine" do
      item("Green tea")

      for text <- [
            "&",
            "|",
            "!",
            "'",
            "\"",
            "\\",
            "(",
            ")",
            ":*",
            "a:b",
            "<->",
            "<",
            "tea & !",
            "tea | | ",
            "\0",
            "🍵",
            "' OR 1=1 --",
            String.duplicate("x", 5_000),
            String.duplicate("a b ", 500)
          ] do
        assert %{rows: rows} = find(text), inspect(text)
        assert is_list(rows)
      end
    end

    test "names that are not plain identifiers are refused: they never come from a user, so this is a bug" do
      assert_raise ArgumentError, fn ->
        Search.search(TestRepo, "search_items; drop table x", "a", select: ["id"])
      end

      assert_raise ArgumentError, fn ->
        Search.search(TestRepo, "search_items", "a", select: ["id, title"])
      end

      assert_raise ArgumentError, fn ->
        Search.search(TestRepo, "search_items", "a", select: ["id"], snippet: "body'")
      end
    end

    test "a change is searchable at once, a delete is gone at once: there is no index to wait for" do
      id = item("Oolong")
      assert id in Enum.map(find("oolong").rows, & &1["id"])

      TestRepo.query!("UPDATE search_items SET title = 'Jasmine' WHERE id = $1", [id])
      refute id in Enum.map(find("oolong", fallback: false).rows, & &1["id"])
      assert id in Enum.map(find("jasmine").rows, & &1["id"])

      TestRepo.query!("DELETE FROM search_items WHERE id = $1", [id])
      refute id in Enum.map(find("jasmine", fallback: false).rows, & &1["id"])
    end

    test "the index is used (not a scan of every row)" do
      for i <- 1..2_000,
          do:
            TestRepo.query!("INSERT INTO search_items (title) VALUES ($1)", [
              "filler #{i} #{:erlang.phash2(i)}"
            ])

      TestRepo.query!("ANALYZE search_items")
      TestRepo.query!("SET LOCAL enable_seqscan = off")

      %{rows: plan} =
        TestRepo.query!(
          "EXPLAIN SELECT id FROM search_items WHERE search @@ to_tsquery('simple', 'filler:*')"
        )

      assert plan |> List.flatten() |> Enum.join("\n") =~ "search_items_search_index"
    end
  end
end
