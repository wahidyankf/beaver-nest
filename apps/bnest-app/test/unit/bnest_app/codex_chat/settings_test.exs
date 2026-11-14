defmodule BnestApp.CodexChat.Domain.SettingsTest do
  use ExUnit.Case, async: true

  alias BnestApp.CodexChat.Domain.Settings

  test "the application default is Terra at medium effort" do
    assert Settings.preferred_model() == "gpt-6.1-terra"
    assert Settings.preferred_reasoning_effort() == "medium"
  end

  # The chip is read-only: it shows the tier name Codex gives each model, then the effort.
  test "the header chip shows the tier name Codex gives each model, then its effort" do
    assert Settings.label("GPT-6-Luna", "medium") == "Luna · medium"
    assert Settings.label("GPT-6.1 Terra", "medium") == "Terra · medium"
    assert Settings.label("GPT-6.1-Sol", "max") == "Sol · max"
  end

  test "a display name without a Codex version prefix is shown whole" do
    assert Settings.label("Local Model", "low") == "Local Model · low"
  end
end
