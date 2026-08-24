defmodule BnestApp.ChatTest do
  use ExUnit.Case, async: true

  alias BnestApp.Chat

  test "counts only distinct assistant updates" do
    {:ok, chat} = Chat.submit(Chat.new(), "Hello")
    chat = Chat.update_assistant(chat, "First")
    unchanged = Chat.update_assistant(chat, "First")

    assert unchanged == chat
  end
end
