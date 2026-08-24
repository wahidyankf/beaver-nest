defmodule BnestApp.ChatTest do
  use ExUnit.Case, async: true

  alias BnestApp.Chat

  test "counts only distinct assistant updates" do
    {:ok, chat} = Chat.submit(Chat.new(), "Hello")
    chat = Chat.update_assistant(chat, "First")
    unchanged = Chat.update_assistant(chat, "First")

    assert unchanged == chat
  end

  test "snapshots only completed chat state" do
    {:ok, busy_chat} = Chat.submit(Chat.new(), "Hello")

    assert Chat.snapshot(busy_chat) == :error
    assert Chat.snapshot(Chat.complete(busy_chat)) == :error
  end

  test "restores an empty versioned snapshot" do
    assert Chat.restore(%{"version" => 1, "thread_id" => nil, "messages" => []}) ==
             {:ok, Chat.new()}
  end

  test "rejects malformed and unsupported snapshots" do
    assert Chat.restore(%{}) == :error

    assert Chat.restore(%{
             "version" => 1,
             "thread_id" => 123,
             "messages" => []
           }) == :error

    assert Chat.restore(%{
             "version" => 1,
             "thread_id" => "thread-1",
             "messages" => [%{"id" => 1, "role" => "visitor"}]
           }) == :error
  end
end
