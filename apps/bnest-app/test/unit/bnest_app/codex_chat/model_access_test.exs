defmodule BnestApp.CodexChat.ModelAccessTest do
  use ExUnit.Case, async: true

  alias BnestApp.CodexChat.Domain.ModelAccess
  alias BnestApp.Test.CodexFixtureModels, as: FixtureModels

  @sol "gpt-6.1-sol"
  @terra "gpt-6.1-terra"
  @luna "gpt-6-luna"

  # The catalog the context offers: ModelCatalog filters the discovered list to these three ids before the
  # access rules see it, so the rules are tested on what a user can actually be offered.
  defp offered, do: Enum.filter(FixtureModels.all(), &(&1.id in [@sol, @terra, @luna]))

  defp model(id), do: Enum.find(FixtureModels.all(), &(&1.id == id))

  defp ids(models), do: Enum.map(models, & &1.id)

  defp resolve(roles, models \\ offered()), do: ModelAccess.resolve(%{"roles" => roles}, models)

  test "only the latest Luna, Terra and Sol are offered; Astra and the older ids are not" do
    assert for(model <- FixtureModels.all(), ModelAccess.offered?(model.id), do: model.id) ==
             [@sol, @terra, @luna]

    refute ModelAccess.offered?("gpt-6-astra")
    refute ModelAccess.offered?("gpt-6-sol")
    refute ModelAccess.offered?("gpt-5.6-terra")
  end

  describe "admin" do
    test "chooses any offered model, defaulting to Terra at medium effort" do
      access = resolve(["admin", "parents"])

      assert access.model_selectable?
      assert access.effort_selectable?
      assert access.available?
      assert ids(access.models) == [@sol, @terra, @luna]
      assert access.model.id == @terra
      assert access.reasoning_effort == "medium"
    end

    test "lists Sol, Terra and Luna in that order, whatever order Codex lists them in" do
      access = resolve(["admin"], [model(@luna), model(@sol), model(@terra)])

      assert ids(access.models) == [@sol, @terra, @luna]
      assert access.model.id == @terra
    end

    test "an unrecognised role has the admin's access" do
      access = resolve(["guest"])

      assert access.model_selectable?
      assert access.effort_selectable?
      assert ids(access.models) == [@sol, @terra, @luna]
    end

    test "a model switch keeps a supported effort" do
      assert {:ok, luna, "high"} = ModelAccess.select_model(resolve(["admin"]), @luna, "high")
      assert luna.id == @luna
    end

    test "a model switch to a model without the current effort falls back to max" do
      admin = resolve(["admin"])

      assert {:ok, luna, "max"} = ModelAccess.select_model(admin, @luna, "ultra")
      assert luna.id == @luna
      assert {:ok, _sol, "ultra"} = ModelAccess.select_model(admin, @sol, "ultra")
    end

    test "an effort the selected model supports is accepted, one it lacks is refused" do
      admin = resolve(["admin"])
      terra = model(@terra)
      luna = model(@luna)

      assert ModelAccess.select_effort(admin, terra, "ultra") == {:ok, "ultra"}
      assert ModelAccess.select_effort(admin, luna, "ultra") == :error
      assert ModelAccess.select_effort(admin, luna, "impossible") == :error
    end
  end

  describe "parents" do
    test "choose Luna or Terra, defaulting to Terra, and never pick an effort" do
      parent = resolve(["parents"])

      assert parent.model_selectable?
      refute parent.effort_selectable?
      assert parent.available?
      assert ids(parent.models) == [@terra, @luna]
      assert parent.model.id == @terra
      assert parent.reasoning_effort == "medium"
    end

    test "may select Luna, and the effort stays medium whatever the saved effort" do
      parent = resolve(["parents"])

      assert {:ok, luna, "medium"} = ModelAccess.select_model(parent, @luna, "high")
      assert luna.id == @luna
      assert {:ok, terra, "medium"} = ModelAccess.select_model(parent, @terra, "max")
      assert terra.id == @terra
    end

    test "may not select Sol or any model outside their two" do
      assert ModelAccess.select_model(resolve(["parents"]), @sol, "medium") == :error
      assert ModelAccess.select_model(resolve(["parents"]), "gpt-6-astra", "medium") == :error
    end

    test "may not choose an effort, not even a supported one" do
      parent = resolve(["parents"])

      assert ModelAccess.select_effort(parent, model(@terra), "high") == :error
      assert ModelAccess.select_effort(parent, model(@terra), "medium") == :error
    end

    test "offer only the choices that support medium effort" do
      luna_without_medium = %{
        model(@luna)
        | supported_reasoning_efforts: ["high"],
          default_reasoning_effort: "high"
      }

      access = resolve(["parents"], [model(@terra), luna_without_medium])

      assert access.available?
      assert access.model_selectable?
      assert ids(access.models) == [@terra]
      assert ModelAccess.select_model(access, @luna, "medium") == :error
    end

    test "list Terra first and then Luna, whatever order Codex lists them in" do
      access = resolve(["parents"], [model(@luna), model(@terra)])

      assert ids(access.models) == [@terra, @luna]
      assert access.model.id == @terra
    end

    test "do not fall back to Luna when Terra is not usable at medium effort" do
      terra = %{model(@terra) | supported_reasoning_efforts: ["low"]}
      access = resolve(["parents"], [terra, model(@luna)])

      refute access.available?
      refute access.model_selectable?
      assert access.model.id == @terra
      assert access.error == "GPT-6.1 Terra is not available in local Codex."
      assert ModelAccess.select_model(access, @luna, "medium") == :error
    end

    test "do not fall back to Luna when Terra is absent from Codex" do
      access = resolve(["parents"], [model(@luna)])

      refute access.available?
      refute access.model_selectable?
      assert access.model.id == @terra
      assert access.error == "GPT-6.1 Terra is not available in local Codex."
    end
  end

  describe "child administrator" do
    test "is locked to Luna at medium effort with no picker, like a child" do
      access = resolve(["children", "admin"])

      refute access.model_selectable?
      refute access.effort_selectable?
      assert access.available?
      assert ids(access.models) == [@luna]
      assert access.model.id == @luna
      assert access.reasoning_effort == "medium"
    end

    test "is locked whatever order the roles arrive in" do
      access = resolve(["admin", "children", "parents"])

      refute access.model_selectable?
      refute access.effort_selectable?
      assert ids(access.models) == [@luna]
      assert access.model.id == @luna
      assert access.reasoning_effort == "medium"
    end

    test "may not select any model or effort, not even Luna" do
      access = resolve(["children", "admin"])

      assert ModelAccess.select_model(access, @terra, "medium") == :error
      assert ModelAccess.select_model(access, @luna, "medium") == :error
      assert ModelAccess.select_effort(access, model(@luna), "medium") == :error
      assert ModelAccess.select_effort(access, model(@luna), "high") == :error
    end

    test "saved settings resolve to Luna at medium effort" do
      access = resolve(["children", "admin"])

      assert {%{id: @luna}, "medium"} = ModelAccess.settle(access, @terra, "high")
      assert {%{id: @luna}, "medium"} = ModelAccess.settle(access, @luna, "high")
    end
  end

  describe "children" do
    test "are locked to Luna at medium effort with no picker" do
      child = resolve(["children"])

      refute child.model_selectable?
      refute child.effort_selectable?
      assert child.available?
      assert ids(child.models) == [@luna]
      assert child.model.id == @luna
      assert child.reasoning_effort == "medium"
    end

    test "may not select any model or effort" do
      child = resolve(["children"])

      assert ModelAccess.select_model(child, @terra, "medium") == :error
      assert ModelAccess.select_model(child, @luna, "medium") == :error
      assert ModelAccess.select_effort(child, model(@luna), "high") == :error
    end

    test "do not fall back to another model when Luna is absent" do
      access = resolve(["children"], [model(@terra)])

      refute access.available?
      refute access.model_selectable?
      assert access.model.id == @luna
      assert access.error == "GPT-6-Luna is not available in local Codex."
    end

    test "are not usable without medium effort" do
      luna = %{model(@luna) | supported_reasoning_efforts: ["high"]}
      access = resolve(["children"], [luna])

      refute access.available?
      assert access.model.id == @luna
      assert access.error == "GPT-6-Luna is not available in local Codex."
    end
  end

  test "a select with no access, or an unavailable one, changes nothing" do
    assert ModelAccess.select_model(nil, @luna, "medium") == :error
    assert ModelAccess.select_effort(nil, model(@terra), "high") == :error

    unavailable = resolve(["children"], [model(@terra)])
    assert ModelAccess.select_model(unavailable, @luna, "medium") == :error
  end

  describe "saved settings resolve to the role's default when the role no longer offers them" do
    for {roles, saved_model, expected} <- [
          {["parents"], "gpt-5.6-terra", @terra},
          {["parents"], "gpt-6-astra", @terra},
          {["parents"], @sol, @terra},
          {["parents"], "removed-model", @terra},
          {["children"], "gpt-6.1-terra", @luna},
          {["children"], "gpt-5.6-luna", @luna},
          {["children"], "removed-model", @luna},
          {["admin"], "gpt-5.6-terra", @terra},
          {["admin"], "gpt-6-astra", @terra},
          {["admin"], "removed-model", @terra}
        ] do
      test "#{Enum.join(roles, ",")} with saved #{saved_model} resolve to #{expected}" do
        access = resolve(unquote(roles))

        assert {%{id: resolved}, _effort} =
                 ModelAccess.settle(access, unquote(saved_model), "medium")

        assert resolved == unquote(expected)
      end
    end

    test "a parent's saved model that the role still offers is kept" do
      access = resolve(["parents"])

      assert {%{id: @luna}, "medium"} = ModelAccess.settle(access, @luna, "high")
    end

    test "a parent's and a child's saved effort is their fixed medium effort" do
      assert {_model, "medium"} = ModelAccess.settle(resolve(["parents"]), @terra, "ultra")
      assert {_model, "medium"} = ModelAccess.settle(resolve(["children"]), @luna, "high")
    end

    test "an admin keeps a saved effort the saved model supports" do
      assert {%{id: @terra}, "high"} = ModelAccess.settle(resolve(["admin"]), @terra, "high")
    end

    test "an admin's saved effort the saved model lacks becomes max" do
      assert {%{id: @luna}, "max"} = ModelAccess.settle(resolve(["admin"]), @luna, "ultra")
    end
  end

  describe "same-tier fallback for a saved model the role no longer offers" do
    test "an admin's old Sol id settles to the latest Sol" do
      access = resolve(["admin"])

      assert {%{id: @sol}, _effort} = ModelAccess.settle(access, "gpt-5.6-sol", "medium")
      assert {%{id: @sol}, _effort} = ModelAccess.settle(access, "gpt-6-sol", "medium")
    end

    test "an admin's old Terra id settles to the latest Terra" do
      access = resolve(["admin"])

      assert {%{id: @terra}, _effort} = ModelAccess.settle(access, "gpt-5.6-terra", "medium")
    end

    test "an admin's old Luna id settles to the latest Luna" do
      access = resolve(["admin"])

      assert {%{id: @luna}, _effort} = ModelAccess.settle(access, "gpt-5.6-luna", "medium")
    end

    test "the tier match ignores case" do
      access = resolve(["admin"])

      assert {%{id: @sol}, _effort} = ModelAccess.settle(access, "GPT-5.6-SOL", "medium")
      assert {%{id: @terra}, _effort} = ModelAccess.settle(access, "Gpt-5.6-Terra", "medium")
    end

    test "an unknown tier still falls back to the role default" do
      assert {%{id: @terra}, _effort} =
               ModelAccess.settle(resolve(["admin"]), "gpt-6-astra", "medium")

      assert {%{id: @luna}, _effort} =
               ModelAccess.settle(resolve(["children"]), "gpt-6-astra", "medium")

      assert {%{id: @terra}, _effort} =
               ModelAccess.settle(resolve(["admin"]), "removed-model", "medium")
    end

    test "a tier the role does not offer still falls back to the role default" do
      assert {%{id: @terra}, _effort} =
               ModelAccess.settle(resolve(["parents"]), "gpt-5.6-sol", "medium")

      assert {%{id: @terra}, _effort} = ModelAccess.settle(resolve(["parents"]), @sol, "medium")
    end

    test "children keep no model choice: every saved model settles to Luna at medium" do
      child = resolve(["children"])

      saved = ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-6-astra", "removed-model"]

      for id <- saved do
        assert {%{id: @luna}, "medium"} = ModelAccess.settle(child, id, "high")
      end
    end

    test "tier_latest names the latest id of a known tier and nil otherwise" do
      assert ModelAccess.tier_latest("gpt-5.6-sol") == @sol
      assert ModelAccess.tier_latest("gpt-6-astra") == nil
      assert ModelAccess.tier_latest(nil) == nil
    end
  end

  test "reasoning_effort keeps a supported effort, then max, then the model's default" do
    luna = model(@luna)

    assert ModelAccess.reasoning_effort(luna, "high") == "high"
    assert ModelAccess.reasoning_effort(luna, "ultra") == "max"
    assert ModelAccess.reasoning_effort(luna) == "medium"

    narrow = %{luna | supported_reasoning_efforts: ["ultra"], default_reasoning_effort: "ultra"}
    assert ModelAccess.reasoning_effort(narrow, "low") == "ultra"
  end

  test "an empty catalog is rejected" do
    assert_raise ArgumentError, "Codex model catalog cannot be empty", fn ->
      ModelAccess.resolve(%{}, [])
    end
  end
end
