defmodule BnestApp.Codex.ModelCatalogConfiguredUnitTest do
  # Not async: it swaps a global application-environment key.
  use ExUnit.Case, async: false

  alias BnestApp.Codex.ModelCatalog
  alias BnestApp.Codex.ModelCatalogUnitTest.StubDiscovery

  test "falls through to discovery when no catalog module is configured" do
    configured = Application.get_env(:bnest_app, :codex_models)
    Application.delete_env(:bnest_app, :codex_models)
    on_exit(fn -> Application.put_env(:bnest_app, :codex_models, configured) end)

    server =
      start_supervised!(
        {ModelCatalog,
         name: nil,
         discovery: StubDiscovery,
         discovery_result:
           {:ok,
            [
              %{
                "id" => "gpt-5.6-luna",
                "display_name" => "GPT-5.6-Luna",
                "default_reasoning_effort" => "medium",
                "supported_reasoning_efforts" => ["low", "medium", "high"],
                "is_default" => true
              }
            ]}}
      )

    assert [%{id: "gpt-5.6-luna"}] = ModelCatalog.all(server)
  end
end
