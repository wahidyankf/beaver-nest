defmodule BnestApp.Codex.ModelCatalogTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BnestApp.Codex.ModelCatalog

  @workspace Path.expand("../../../../../..", __DIR__)
  @fixture_runner Path.join(@workspace, "apps/bnest-app/test/support/codex_fixture_models.mjs")

  test "discovers and normalizes every picker model from a local runner" do
    catalog =
      start_supervised!(
        {ModelCatalog,
         name: nil,
         models_runner: @fixture_runner,
         working_directory: @workspace,
         node: System.find_executable("node")}
      )

    assert length(ModelCatalog.all(catalog)) == 7

    assert {:ok, %{display_name: "GPT-5.6-Luna"} = luna} =
             ModelCatalog.fetch("gpt-5.6-luna", catalog)

    assert ModelCatalog.reasoning_effort(luna, "high") == "high"
    assert ModelCatalog.reasoning_effort(luna, "ultra") == "medium"

    assert ModelCatalog.fetch("hidden-or-unknown", catalog) == :error
  end

  test "uses configured local discovery when no test catalog is supplied" do
    original_models = Application.get_env(:bnest_app, :codex_models)
    original_codex = Application.fetch_env!(:bnest_app, :codex)

    Application.delete_env(:bnest_app, :codex_models)

    Application.put_env(
      :bnest_app,
      :codex,
      Keyword.put(original_codex, :models_runner, @fixture_runner)
    )

    on_exit(fn ->
      Application.put_env(:bnest_app, :codex_models, original_models)
      Application.put_env(:bnest_app, :codex, original_codex)
    end)

    catalog = start_supervised!({ModelCatalog, name: nil})
    assert length(ModelCatalog.all(catalog)) == 7
  end

  test "the production model runner is located in the packaged application" do
    assert ModelCatalog.bundled_models_runner() ==
             Application.app_dir(:bnest_app, "priv/codex/list_models.mjs")
  end

  test "uses a safe Terra fallback for an invalid catalog" do
    log =
      capture_log(fn ->
        catalog = start_supervised!({ModelCatalog, name: nil, models: nil})
        assert ModelCatalog.default(catalog).id == "gpt-5.6-terra"

        {:ok, second_catalog} = ModelCatalog.start_link(name: nil, models: [nil])
        assert ModelCatalog.default(second_catalog).id == "gpt-5.6-terra"
        GenServer.stop(second_catalog)
      end)

    assert log =~ "using the Terra fallback"
  end

  test "uses the fallback when the local discovery process cannot start" do
    log =
      capture_log(fn ->
        catalog =
          start_supervised!(
            {ModelCatalog,
             name: nil, models_runner: @fixture_runner, working_directory: @workspace, node: nil}
          )

        assert ModelCatalog.all(catalog) == [ModelCatalog.default(catalog)]
      end)

    assert log =~ "model discovery failed"
  end

  test "chooses the declared default and supported effort when Terra and medium are absent" do
    models = [
      %{
        id: "local-first",
        display_name: "Local First",
        default_reasoning_effort: "low",
        supported_reasoning_efforts: ["low"],
        is_default: false
      },
      %{
        id: "local-default",
        display_name: "Local Default",
        default_reasoning_effort: "high",
        supported_reasoning_efforts: ["high"],
        is_default: true
      }
    ]

    catalog = start_supervised!({ModelCatalog, name: nil, models: models})
    selected = ModelCatalog.default(catalog)

    assert selected.id == "local-default"
    assert ModelCatalog.reasoning_effort(selected) == "high"
    assert ModelCatalog.reasoning_effort(selected, "low") == "high"
  end

  test "uses the first valid model when no preferred or declared default exists" do
    models = [
      %{
        "id" => "local-first",
        "display_name" => "Local First",
        "default_reasoning_effort" => "medium",
        "supported_reasoning_efforts" => ["medium"],
        "is_default" => false
      }
    ]

    catalog = start_supervised!({ModelCatalog, name: nil, models: models})
    assert ModelCatalog.default(catalog).id == "local-first"
  end
end
