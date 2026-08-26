defmodule BnestApp.ChatTest do
  use ExUnit.Case, async: true

  alias BnestApp.Chat

  test "counts only distinct assistant updates" do
    {:ok, chat} = Chat.submit(Chat.new(), "Hello")
    chat = Chat.update_assistant(chat, "First")
    unchanged = Chat.update_assistant(chat, "First")

    assert unchanged == chat
  end

  test "checkpoints an active chat before a transport supplies a thread ID" do
    {:ok, busy_chat} = Chat.submit(Chat.new(), "Hello")

    assert {:ok,
            %{
              "version" => 3,
              "pending_turn" => %{
                "assistant_message_id" => 2,
                "continuation_attempted" => false,
                "prompt" => "Hello"
              }
            }} = Chat.snapshot(busy_chat)

    assert {:ok, %{"thread_id" => nil, "messages" => messages}} =
             Chat.snapshot(Chat.complete(busy_chat))

    assert Enum.map(messages, & &1["role"]) == ["visitor", "assistant"]
  end

  test "continues an interrupted turn once without duplicating the recovery request" do
    assert {:error, :none} = Chat.continuation_prompt(Chat.new())

    {:ok, chat} = Chat.submit(Chat.new(), "Hello")

    assert {:ok, "Hello", recovered} = Chat.continuation_prompt(chat)
    assert recovered.pending_turn.continuation_attempted == true
    assert {:error, :already_attempted} = Chat.continuation_prompt(recovered)

    resumed = %{
      recovered
      | thread_id: "thread-1",
        pending_turn: %{recovered.pending_turn | continuation_attempted: false}
    }

    assert {:ok, prompt, _recovered} = Chat.continuation_prompt(resumed)
    assert prompt =~ "Continue the previous answer"
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

  test "enforces a role-required model even while a restored turn is active" do
    {:ok, busy} = Chat.submit(Chat.new("gpt-5.6-terra", "high"), "Continue")

    restricted = Chat.enforce_model(busy, "gpt-5.6-luna", "medium")

    assert restricted.model == "gpt-5.6-luna"
    assert restricted.reasoning_effort == "medium"
    assert restricted.busy
    assert restricted.pending_turn == busy.pending_turn
  end

  test "snapshots the selected model and effort" do
    chat = Chat.new("gpt-5.6-luna", "medium")

    assert {:ok,
            %{
              "version" => 3,
              "model" => "gpt-5.6-luna",
              "reasoning_effort" => "medium"
            }} = Chat.snapshot(chat)

    assert Chat.snapshot(%{chat | model: ""}) == :error
    assert Chat.snapshot(%{chat | thread_id: 123}) == :error
    assert Chat.snapshot(%{chat | busy: true}) == :error
    assert Chat.snapshot(:invalid) == :error
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

    assert Chat.restore(%{
             "version" => 3,
             "thread_id" => nil,
             "model" => "gpt-5.6-luna",
             "reasoning_effort" => "medium",
             "messages" => [
               %{"id" => 1, "role" => "visitor", "content" => "Hello", "streaming" => false},
               %{"id" => 2, "role" => "assistant", "content" => "", "streaming" => true}
             ],
             "pending_turn" => %{
               "prompt" => "Hello",
               "assistant_message_id" => 3,
               "continuation_attempted" => false
             }
           }) == :error

    assert Chat.restore(%{
             "version" => 3,
             "thread_id" => nil,
             "model" => "gpt-5.6-luna",
             "reasoning_effort" => "medium",
             "messages" => [],
             "pending_turn" => %{"prompt" => "Hello"}
           }) == :error
  end

  test "rejects an interrupted snapshot whose assistant checkpoint is stale" do
    {:ok, chat} = Chat.submit(Chat.new(), "Hello")
    {:ok, snapshot} = Chat.snapshot(chat)

    stale = put_in(snapshot, ["pending_turn", "assistant_message_id"], 3)

    assert Chat.restore(stale) == :error
  end
end
