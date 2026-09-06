defmodule BnestApp.Codex.ModelCatalogUnitTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BnestApp.Codex.ModelCatalog

  @luna %{
    "id" => "gpt-5.6-luna",
    "display_name" => "GPT-5.6-Luna",
    "default_reasoning_effort" => "medium",
    "supported_reasoning_efforts" => ["low", "medium", "high"],
    "is_default" => true
  }

  @nova %{
    @luna
    | "id" => "gpt-5.6-nova",
      "display_name" => "GPT-5.6-Nova",
      "is_default" => false
  }

  @fallback_id "gpt-5.6-terra"

  defmodule StubDiscovery do
    @moduledoc false
    @behaviour BnestApp.Codex.ModelDiscovery

    @impl true
    def discover(options), do: Keyword.fetch!(options, :discovery_result)
  end

  # A unique child id lets one test start more than one unnamed catalog. `make_ref/0` is
  # used because the unit boundary policy forbids the operating-system counter alternative.
  defp catalog(options) do
    start_supervised!(
      Supervisor.child_spec({ModelCatalog, Keyword.put(options, :name, nil)}, id: make_ref())
    )
  end

  test "normalizes supplied models and indexes them by id" do
    server = catalog(models: [@luna, @nova])

    assert [%{id: "gpt-5.6-luna"}, %{id: "gpt-5.6-nova"}] = ModelCatalog.all(server)
    assert {:ok, %{display_name: "GPT-5.6-Luna"}} = ModelCatalog.fetch("gpt-5.6-luna", server)
    assert ModelCatalog.fetch("never-offered", server) == :error
  end

  test "accepts atom-keyed models identically to string-keyed ones" do
    atom_keyed = %{
      id: "gpt-5.6-luna",
      display_name: "GPT-5.6-Luna",
      default_reasoning_effort: "medium",
      supported_reasoning_efforts: ["low", "medium", "high"],
      is_default: true
    }

    assert ModelCatalog.all(catalog(models: [atom_keyed])) ==
             ModelCatalog.all(catalog(models: [@luna]))
  end

  test "keeps the first model when Codex repeats an id" do
    assert [%{display_name: "GPT-5.6-Luna"}] =
             ModelCatalog.all(catalog(models: [@luna, %{@luna | "display_name" => "Duplicate"}]))
  end

  test "default/1 prefers the model Codex flags as default" do
    assert %{id: "gpt-5.6-luna"} = ModelCatalog.default(catalog(models: [@nova, @luna]))
  end

  test "default/1 falls back to the first model when none is flagged" do
    unflagged = %{@luna | "is_default" => false}
    assert %{id: "gpt-5.6-luna"} = ModelCatalog.default(catalog(models: [unflagged, @nova]))
  end

  test "reasoning_effort honours a supported request and rejects an unsupported one" do
    [luna] = ModelCatalog.all(catalog(models: [@luna]))

    assert ModelCatalog.reasoning_effort(luna, "high") == "high"
    assert ModelCatalog.reasoning_effort(luna, "ultra") == "medium"
  end

  # Each clause of the validator gets its own rejection, so a loosened condition fails here
  # rather than silently widening what the picker will offer.
  for {label, invalid} <- [
        {"a blank id", %{"id" => ""}},
        {"an oversized display name", %{"display_name" => String.duplicate("n", 129)}},
        {"a non-string id", %{"id" => 42}},
        {"an unknown default effort", %{"default_reasoning_effort" => "turbo"}},
        {"an empty supported list", %{"supported_reasoning_efforts" => []}},
        {"an unknown supported effort", %{"supported_reasoning_efforts" => ["turbo"]}},
        {"a default outside the supported list",
         %{"supported_reasoning_efforts" => ["low"], "default_reasoning_effort" => "high"}},
        {"a non-boolean default flag", %{"is_default" => "yes"}}
      ] do
    test "falls back to Terra for a model with #{label}" do
      models = [Map.merge(@luna, unquote(Macro.escape(invalid)))]

      log =
        capture_log(fn ->
          assert [%{id: @fallback_id}] = ModelCatalog.all(catalog(models: models))
        end)

      assert log =~ "no valid picker models"
    end
  end

  test "falls back to Terra when Codex returns something that is not a list" do
    log =
      capture_log(fn ->
        assert [%{id: @fallback_id}] = ModelCatalog.all(catalog(models: %{"id" => "luna"}))
      end)

    assert log =~ "no valid picker models"
  end

  test "normalizes models returned by an injected discovery adapter" do
    server =
      catalog(
        models_runner: "unused-by-the-stub",
        discovery: StubDiscovery,
        discovery_result: {:ok, [@luna]}
      )

    assert [%{id: "gpt-5.6-luna"}] = ModelCatalog.all(server)
  end

  test "falls back to Terra when the discovery adapter fails" do
    log =
      capture_log(fn ->
        server =
          catalog(
            models_runner: "unused-by-the-stub",
            discovery: StubDiscovery,
            discovery_result: :error
          )

        assert [%{id: @fallback_id}] = ModelCatalog.all(server)
      end)

    assert log =~ "discovery failed"
  end

  test "registers under a supplied name" do
    server =
      start_supervised!(
        Supervisor.child_spec({ModelCatalog, name: {:global, make_ref()}, models: [@luna]},
          id: make_ref()
        )
      )

    assert [%{id: "gpt-5.6-luna"}] = ModelCatalog.all(:sys.get_state(server) && server)
  end

  test "reasoning_effort/1 falls back to the preferred effort" do
    [luna] = ModelCatalog.all(catalog(models: [@luna]))
    assert ModelCatalog.reasoning_effort(luna) in luna.supported_reasoning_efforts
  end

  test "reasoning_effort returns the model default when neither request nor preference fits" do
    narrow = %{
      @luna
      | "supported_reasoning_efforts" => ["ultra"],
        "default_reasoning_effort" => "ultra"
    }

    [model] = ModelCatalog.all(catalog(models: [narrow]))

    assert ModelCatalog.reasoning_effort(model, "low") == "ultra"
  end

  test "falls back to Terra when an entry is not a map at all" do
    log =
      capture_log(fn ->
        assert [%{id: @fallback_id}] = ModelCatalog.all(catalog(models: ["not-a-model"]))
      end)

    assert log =~ "no valid picker models"
  end

  test "reads the configured catalog module when no models are supplied" do
    configured = Application.fetch_env!(:bnest_app, :codex_models)
    assert ModelCatalog.all(catalog([])) == ModelCatalog.all(catalog(models: configured.all()))
  end
end
