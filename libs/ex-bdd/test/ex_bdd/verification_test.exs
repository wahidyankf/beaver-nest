defmodule ExBdd.VerificationTest do
  use ExUnit.Case, async: false

  @fixture_root Path.expand("../fixtures/verification", __DIR__)

  test "verifies and counts the complete expanded corpus" do
    result =
      ExBdd.verify_features!(
        features: [Path.join(@fixture_root, "valid.feature")],
        steps: [Path.join(@fixture_root, "steps.exs")],
        support: []
      )

    assert result.feature_count == 1
    assert result.scenario_count == 1
    assert result.step_count == 3
    assert result.binding_count == 3
  end

  test "counts every scenario-outline row and its steps" do
    result = verify("outline.feature", "steps.exs")

    assert result.scenario_count == 2
    assert result.step_count == 6
  end

  test "rejects an empty feature corpus" do
    assert_verification_error("No feature files", fn ->
      ExBdd.verify_features!(
        features: [Path.join(@fixture_root, "missing/**/*.feature")],
        steps: [Path.join(@fixture_root, "steps.exs")],
        support: []
      )
    end)
  end

  test "rejects a feature without scenarios" do
    assert_verification_error("has no scenarios", fn -> verify("empty.feature", "steps.exs") end)
  end

  test "rejects scenarios that expand to no executable examples" do
    assert_verification_error("expands to no executable scenarios", fn ->
      verify("unexpanded.feature", "steps.exs")
    end)
  end

  test "rejects scenarios without an explicit When" do
    assert_verification_error("requires an explicit When", fn ->
      verify("missing_when.feature", "steps.exs")
    end)
  end

  test "rejects scenarios without an explicit Then" do
    assert_verification_error("requires an explicit Then", fn ->
      verify("missing_then.feature", "steps.exs")
    end)
  end

  test "rejects undefined steps" do
    assert_verification_error("has no matching binding", fn ->
      verify("undefined.feature", "steps.exs")
    end)
  end

  test "rejects ambiguous steps" do
    assert_verification_error("matches 2 bindings", fn ->
      verify("valid.feature", "ambiguous_steps.exs")
    end)
  end

  test "rejects unused bindings" do
    assert_verification_error("is not used", fn ->
      verify("valid.feature", "unused_steps.exs")
    end)
  end

  test "compile_features!/1 cannot bypass strict verification" do
    assert_verification_error("requires an explicit When", fn ->
      ExBdd.compile_features!(
        features: [Path.join(@fixture_root, "missing_when.feature")],
        steps: [Path.join(@fixture_root, "steps.exs")],
        support: []
      )
    end)
  end

  test "default public entry points perform strict discovery" do
    assert_verification_error("requires an explicit", fn -> ExBdd.verify_features!() end)
    assert_verification_error("requires an explicit", fn -> ExBdd.compile_features!() end)

    assert_verification_error("requires an explicit", fn ->
      ExBdd.Compiler.compile_features!()
    end)
  end

  test "the public compiler returns executable modules for a valid corpus" do
    [module] =
      ExBdd.compile_features!(
        features: [Path.join(@fixture_root, "valid.feature")],
        steps: [Path.join(@fixture_root, "steps.exs")],
        support: []
      )

    {result, _output} = ExBdd.BehaviorCase.run_isolated([module])

    assert result.total == 1
    assert result.failures == 0
  end

  defp verify(feature, steps) do
    ExBdd.verify_features!(
      features: [Path.join(@fixture_root, feature)],
      steps: [Path.join(@fixture_root, steps)],
      support: []
    )
  end

  defp assert_verification_error(expected, fun) do
    result =
      try do
        fun.()
        :no_error
      rescue
        error -> error
      end

    refute result == :no_error
    assert result.__struct__ == ExBdd.VerificationError
    assert Exception.message(result) =~ expected
  end
end
