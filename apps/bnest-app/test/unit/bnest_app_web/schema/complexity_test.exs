defmodule BnestAppWeb.Schema.ComplexityTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.Schema.Complexity

  describe "page/2" do
    test "prices a page at its size times the price of one message" do
      assert Complexity.page(%{limit: 50}, 102) == 5_100
      assert Complexity.page(%{limit: 1}, 102) == 102
    end

    test "prices an omitted limit at the largest page, which is also the default" do
      assert Complexity.page(%{}, 102) == 5_100
    end

    test "prices a limit the resolver refuses at the largest page" do
      assert Complexity.page(%{limit: 0}, 1) == 50
      assert Complexity.page(%{limit: -1}, 1) == 50
      assert Complexity.page(%{limit: 51}, 1) == 50
    end
  end

  describe "body_html/1" do
    test "adds the body weight to the price of its children" do
      assert Complexity.body_html(0) == 100
      assert Complexity.body_html(3) == 103
    end
  end

  describe "pipeline/2" do
    test "runs the envelope in place of the complexity result phase, after the analysis" do
      config = %{schema_mod: BnestAppWeb.Schema, conn_private: %{http_method: "POST"}}

      phases =
        config
        |> Complexity.pipeline(
          analyze_complexity: true,
          max_complexity: Complexity.max_complexity()
        )
        |> Enum.map(fn
          {phase, _options} -> phase
          phase -> phase
        end)

      analysis = Enum.find_index(phases, &(&1 == Absinthe.Phase.Document.Complexity.Analysis))
      envelope = Enum.find_index(phases, &(&1 == BnestAppWeb.Schema.Complexity.Envelope))

      assert is_integer(envelope)
      assert envelope == analysis + 1
      refute Absinthe.Phase.Document.Complexity.Result in phases
    end
  end

  test "the budget admits a normal page and refuses a page that repeats bodyHtml" do
    # The connection's children: `id` (1) and `bodyHtml` (100) of each message, `nodes` itself (1), `hasOlder` and
    # `hasNewer` (1 each). Ten aliases repeat `bodyHtml` ten times.
    one_page = Complexity.page(%{limit: 50}, 1 + 1 + 100 + 1 + 1)
    ten_aliases = Complexity.page(%{limit: 50}, 1 + 1 + 10 * 100 + 1 + 1)

    assert one_page <= Complexity.max_complexity()
    assert ten_aliases > Complexity.max_complexity()
  end
end
