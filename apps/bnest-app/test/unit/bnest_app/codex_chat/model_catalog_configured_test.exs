defmodule BnestApp.CodexChat.ModelCatalogConfiguredUnitTest do
  # Not async: it swaps a global application-environment key.
  use ExUnit.Case, async: false

  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.ModelCatalog
  alias BnestApp.CodexChat.ModelCatalogUnitTest.StubDiscovery

  test "discovers through the configured model discovery when none is supplied" do
    configured = Application.fetch_env!(:bnest_app, CodexChat)

    Application.put_env(
      :bnest_app,
      CodexChat,
      Keyword.put(configured, :model_discovery, StubDiscovery)
    )

    on_exit(fn -> Application.put_env(:bnest_app, CodexChat, configured) end)

    server =
      start_supervised!(
        {ModelCatalog,
         name: nil,
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
