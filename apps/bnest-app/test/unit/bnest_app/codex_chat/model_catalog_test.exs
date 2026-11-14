defmodule BnestApp.CodexChat.ModelCatalogUnitTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.ModelCatalog

  @luna %{
    "id" => "gpt-6-luna",
    "display_name" => "GPT-6-Luna",
    "default_reasoning_effort" => "medium",
    "supported_reasoning_efforts" => ["low", "medium", "high"],
    "is_default" => true
  }

  @sol %{
    @luna
    | "id" => "gpt-6.1-sol",
      "display_name" => "GPT-6.1-Sol",
      "is_default" => false
  }

  @terra %{
    @luna
    | "id" => "gpt-6.1-terra",
      "display_name" => "GPT-6.1 Terra",
      "is_default" => false
  }

  # Models a user must never be offered: Astra and the older ids.
  @astra %{@luna | "id" => "gpt-6-astra", "display_name" => "GPT-6-Astra", "is_default" => false}
  @older_terra %{@terra | "id" => "gpt-5.6-terra", "display_name" => "GPT-5.6-Terra"}

  @fallback_id "gpt-6.1-terra"

  defmodule StubDiscovery do
    @moduledoc false
    @behaviour BnestApp.CodexChat.Ports.ModelDiscovery

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
    server = catalog(models: [@luna, @terra])

    assert [%{id: "gpt-6-luna"}, %{id: "gpt-6.1-terra"}] = ModelCatalog.all(server)
    assert {:ok, %{display_name: "GPT-6-Luna"}} = ModelCatalog.fetch("gpt-6-luna", server)
    assert ModelCatalog.fetch("never-offered", server) == :error
  end

  test "offers only the latest Luna, Terra and Sol, dropping Astra and the older ids" do
    server = catalog(models: [@astra, @older_terra, @sol, @luna, @terra])

    assert [%{id: "gpt-6.1-sol"}, %{id: "gpt-6-luna"}, %{id: "gpt-6.1-terra"}] =
             ModelCatalog.all(server)

    assert ModelCatalog.fetch("gpt-6-astra", server) == :error
    assert ModelCatalog.fetch("gpt-5.6-terra", server) == :error
  end

  test "a discovered catalog holding only retired models falls back to the Terra fallback" do
    log =
      capture_log(fn ->
        assert [%{id: @fallback_id}] = ModelCatalog.all(catalog(models: [@astra, @older_terra]))
      end)

    assert log =~ "no valid picker models"
  end

  test "the Terra fallback is named and specified as Codex names it" do
    log =
      capture_log(fn ->
        assert [fallback] = ModelCatalog.all(catalog(models: []))

        assert fallback == %{
                 id: "gpt-6.1-terra",
                 display_name: "GPT-6.1 Terra",
                 default_reasoning_effort: "low",
                 supported_reasoning_efforts: ~w(low medium high xhigh max ultra),
                 is_default: false
               }
      end)

    assert log =~ "no valid picker models"
  end

  test "accepts atom-keyed models identically to string-keyed ones" do
    atom_keyed = %{
      id: "gpt-6-luna",
      display_name: "GPT-6-Luna",
      default_reasoning_effort: "medium",
      supported_reasoning_efforts: ["low", "medium", "high"],
      is_default: true
    }

    assert ModelCatalog.all(catalog(models: [atom_keyed])) ==
             ModelCatalog.all(catalog(models: [@luna]))
  end

  test "keeps the first model when Codex repeats an id" do
    assert [%{display_name: "GPT-6-Luna"}] =
             ModelCatalog.all(catalog(models: [@luna, %{@luna | "display_name" => "Duplicate"}]))
  end

  test "an invalid entry for a model that is not offered does not empty the catalog" do
    astra_with_new_effort = %{@astra | "default_reasoning_effort" => "turbo"}

    assert [%{id: "gpt-6-luna"}, %{id: "gpt-6.1-terra"}] =
             ModelCatalog.all(catalog(models: [astra_with_new_effort, @luna, @terra]))
  end

  test "a malformed offered entry falls back to the Terra fallback, keeping no other model" do
    malformed_luna = %{@luna | "default_reasoning_effort" => "turbo"}

    log =
      capture_log(fn ->
        assert [%{id: @fallback_id}] =
                 ModelCatalog.all(catalog(models: [malformed_luna, @terra]))
      end)

    assert log =~ "no valid picker models"
  end

  test "default/1 prefers Terra when it is offered" do
    assert %{id: "gpt-6.1-terra"} = ModelCatalog.default(catalog(models: [@luna, @terra]))
  end

  test "default/1 prefers the model Codex flags as default when Terra is absent" do
    flagged_sol = %{@sol | "is_default" => true}
    unflagged_luna = %{@luna | "is_default" => false}

    assert %{id: "gpt-6.1-sol"} =
             ModelCatalog.default(catalog(models: [unflagged_luna, flagged_sol]))
  end

  test "default/1 falls back to the first model when none is flagged" do
    unflagged = %{@luna | "is_default" => false}
    assert %{id: "gpt-6-luna"} = ModelCatalog.default(catalog(models: [unflagged, @sol]))
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
    test "falls back to the Terra fallback for a model with #{label}" do
      models = [Map.merge(@luna, unquote(Macro.escape(invalid)))]

      log =
        capture_log(fn ->
          assert [%{id: @fallback_id}] = ModelCatalog.all(catalog(models: models))
        end)

      assert log =~ "no valid picker models"
    end
  end

  test "falls back to the Terra fallback when Codex returns something that is not a list" do
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

    assert [%{id: "gpt-6-luna"}] = ModelCatalog.all(server)
  end

  test "falls back to the Terra fallback when the discovery adapter fails" do
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

    assert [%{id: "gpt-6-luna"}] = ModelCatalog.all(:sys.get_state(server) && server)
  end

  test "falls back to the Terra fallback when an entry is not a map at all" do
    log =
      capture_log(fn ->
        assert [%{id: @fallback_id}] = ModelCatalog.all(catalog(models: ["not-a-model"]))
      end)

    assert log =~ "no valid picker models"
  end

  test "discovers through the configured model discovery when no models are supplied" do
    {:ok, configured} = CodexChat.adapter(:model_discovery).discover([])
    assert ModelCatalog.all(catalog([])) == ModelCatalog.all(catalog(models: configured))
  end
end
