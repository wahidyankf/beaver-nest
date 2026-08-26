defmodule BnestApp.Codex.ModelAccessTest do
  use ExUnit.Case, async: true

  alias BnestApp.Codex.{FixtureModels, ModelAccess}

  test "admins retain every discovered model and model selection" do
    models = FixtureModels.all()
    access = ModelAccess.resolve(%{"roles" => ["admin", "parents"]}, models)

    assert access.selectable?
    assert access.available?
    assert access.models == models
    assert access.model.id == "gpt-5.6-terra"
    assert access.reasoning_effort == "medium"
  end

  test "parents and children receive their fixed medium-effort model" do
    models = FixtureModels.all()

    parent = ModelAccess.resolve(%{"roles" => ["parents"]}, models)
    child = ModelAccess.resolve(%{"roles" => ["children"]}, models)

    refute parent.selectable?
    assert parent.available?
    assert parent.model.id == "gpt-5.6-terra"
    assert parent.reasoning_effort == "medium"

    refute child.selectable?
    assert child.available?
    assert child.model.id == "gpt-5.6-luna"
    assert child.reasoning_effort == "medium"
  end

  test "a fixed role does not fall back to another model when its required model is absent" do
    models = [FixtureModels.fetch_by_id!("gpt-5.6-terra")]
    access = ModelAccess.resolve(%{"roles" => ["children"]}, models)

    refute access.available?
    refute access.selectable?
    assert access.model.id == "gpt-5.6-luna"
    assert access.error == "GPT-5.6-Luna is not available in local Codex."
  end

  test "an unavailable required model is not usable without medium effort" do
    terra =
      FixtureModels.fetch_by_id!("gpt-5.6-terra")
      |> Map.put(:supported_reasoning_efforts, ["low"])

    access = ModelAccess.resolve(%{"roles" => ["parents"]}, [terra])

    refute access.available?
    assert access.model == terra
    assert access.error == "GPT-5.6-Terra is not available in local Codex."
  end

  test "unknown roles retain the catalog and an empty catalog is rejected" do
    models = FixtureModels.all()
    access = ModelAccess.resolve(%{"roles" => ["guest"]}, models)

    assert access.selectable?
    assert access.models == models

    assert_raise ArgumentError, "Codex model catalog cannot be empty", fn ->
      ModelAccess.resolve(%{}, [])
    end
  end
end
