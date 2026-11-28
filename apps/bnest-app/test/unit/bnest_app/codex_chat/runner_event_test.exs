defmodule BnestApp.CodexChat.RunnerEventTest do
  use ExUnit.Case, async: true

  alias BnestApp.CodexChat.Domain.RunnerEvent

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A runner exit or invalid runner output shows one fixed line
  test "a runner exit reports its status as one fixed line" do
    assert RunnerEvent.exit_message(3) == "Codex runner exited with status 3."
  end

  test "unparseable runner output reports one fixed line" do
    assert RunnerEvent.invalid_data_message() == "Codex runner returned invalid data."
  end
end
