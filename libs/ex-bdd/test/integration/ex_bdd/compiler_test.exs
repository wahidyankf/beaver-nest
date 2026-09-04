defmodule ExBdd.CompilerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias ExBdd.Gherkin.{Feature, Scenario}

  defmodule MarkerCase do
    use ExUnit.CaseTemplate

    using do
      quote do
        def __ex_bdd_case_template__, do: :marker_case
      end
    end
  end

  describe "compile_feature!/4" do
    test "uses the configured ExUnit case template" do
      feature = %Feature{
        name: "case template",
        scenarios: [%Scenario{name: "a scenario", steps: [], tags: [], line: 1}],
        tags: []
      }

      feature =
        Map.put(
          feature,
          :file,
          "test/features/case_template_#{System.unique_integer([:positive])}.feature"
        )

      module =
        ExBdd.Compiler.compile_feature!(feature, %{}, [], case_template: MarkerCase)

      assert function_exported?(module, :__ex_bdd_case_template__, 0)
      assert module.__ex_bdd_case_template__() == :marker_case
    end

    test "generates a valid module for absolute paths with punctuation" do
      feature = %Feature{
        name: "absolute path",
        scenarios: [%Scenario{name: "a scenario", steps: [], tags: [], line: 1}],
        tags: []
      }

      feature =
        Map.put(
          feature,
          :file,
          Path.join([
            System.tmp_dir!(),
            "beaver-nest",
            "nested specs",
            "home-page_#{System.unique_integer([:positive])}.feature"
          ])
        )

      module = ExBdd.Compiler.compile_feature!(feature, %{}, [])

      assert is_atom(module)
      assert function_exported?(module, :__step_registry__, 0)
    end

    test "rejects a non-module case template" do
      feature = %Feature{name: "invalid case", scenarios: [], tags: []}
      feature = Map.put(feature, :file, "invalid_case.feature")

      assert_raise ArgumentError, ~r/:case_template must be a module/, fn ->
        ExBdd.Compiler.compile_feature!(feature, %{}, [], case_template: "ExUnit.Case")
      end
    end
  end

  describe "warn_on_empty_feature/1" do
    test "warns when the feature has zero scenarios" do
      feature = %Feature{name: "empty", scenarios: [], tags: []}
      feature = Map.put(feature, :file, "test/features/empty.feature")

      stderr = capture_io(:stderr, fn -> ExBdd.Compiler.warn_on_empty_feature(feature) end)

      assert stderr =~ "test/features/empty.feature"
      assert stderr =~ "zero scenarios"
    end

    test "is silent when the feature has at least one scenario" do
      feature = %Feature{
        name: "non-empty",
        scenarios: [%Scenario{name: "a", steps: [], tags: [], line: 1}],
        tags: []
      }

      feature = Map.put(feature, :file, "test/features/non_empty.feature")

      stderr = capture_io(:stderr, fn -> ExBdd.Compiler.warn_on_empty_feature(feature) end)

      assert stderr == ""
    end
  end
end
