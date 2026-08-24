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

  test "changes models only between turns" do
    chat = Chat.new()
    assert Chat.new("gpt-5.6-luna").reasoning_effort == "medium"

    assert {:ok, selected} = Chat.select_model(chat, "gpt-5.6-luna", "medium")
    assert selected.model == "gpt-5.6-luna"
    assert selected.reasoning_effort == "medium"

    {:ok, busy} = Chat.submit(selected, "Hello")
    assert Chat.select_model(busy, "gpt-5.6-sol", "low") == {:error, busy}
    assert Chat.select_model(chat, "", "medium") == {:error, chat}
    assert Chat.select_model(chat, "gpt-5.6-luna", "impossible") == {:error, chat}
  end

  test "snapshots the selected model and effort" do
    chat = Chat.new("gpt-5.6-luna", "medium")

    assert {:ok,
            %{
              "version" => 2,
              "model" => "gpt-5.6-luna",
              "reasoning_effort" => "medium"
            }} = Chat.snapshot(chat)

    assert Chat.snapshot(%{chat | model: ""}) == :error
    assert Chat.snapshot(%{chat | thread_id: 123}) == :error
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

    assert Chat.restore(%{
             "version" => 2,
             "thread_id" => nil,
             "model" => 123,
             "reasoning_effort" => "medium",
             "messages" => []
           }) == :error

    assert Chat.restore(%{
             "version" => 2,
             "thread_id" => nil,
             "model" => "gpt-5.6-luna",
             "reasoning_effort" => "impossible",
             "messages" => []
           }) == :error
  end
end
