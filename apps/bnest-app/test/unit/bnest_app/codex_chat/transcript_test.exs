defmodule BnestApp.CodexChat.TranscriptTest do
  use ExUnit.Case, async: true

  alias BnestApp.CodexChat.Domain.Transcript

  test "counts only distinct assistant updates" do
    {:ok, chat} = Transcript.submit(Transcript.new(), "Hello")
    chat = Transcript.update_assistant(chat, "answer", "First")
    unchanged = Transcript.update_assistant(chat, "answer", "First")

    assert unchanged == chat
  end

  test "retains public reasoning and prior assistant progress when a new item becomes final" do
    {:ok, chat} = Transcript.submit(Transcript.new(), "Hello")

    chat =
      chat
      |> Transcript.update_progress("reasoning", :reasoning, "Checking the request")
      |> Transcript.update_assistant("progress", "Looking up the answer")
      |> Transcript.update_assistant("final", "Here is the answer")
      |> Transcript.complete()

    assert [%{role: :visitor}, assistant] = chat.messages
    assert assistant.content == "Here is the answer"
    assert assistant.streaming == false

    assert assistant.progress == [
             %{item_id: "reasoning", kind: :reasoning, content: "Checking the request"},
             %{item_id: "progress", kind: :status, content: "Looking up the answer"}
           ]

    assert {:ok, snapshot} = Transcript.snapshot(chat)
    assert snapshot["version"] == 4
    assert {:ok, restored} = Transcript.restore(snapshot)
    assert List.last(restored.messages).progress == assistant.progress
  end

  test "updates only valid public progress and restores compatible snapshots safely" do
    {:ok, chat} = Transcript.submit(Transcript.new(), "Hello")

    assert Transcript.update_assistant(chat, "Legacy answer")
           |> Map.fetch!(:messages)
           |> List.last()
           |> Map.fetch!(:active_item_id) == "assistant-message"

    assert Transcript.update_assistant(chat, "", "Ignored") == chat
    assert Transcript.update_assistant(chat, :invalid, "Ignored") == chat
    assert Transcript.update_progress(chat, "progress", :reasoning, " ") == chat
    assert Transcript.update_progress(chat, "", :reasoning, "Ignored") == chat
    assert Transcript.update_progress(chat, :invalid, :reasoning, "Ignored") == chat

    updated =
      chat
      |> Transcript.update_progress("progress", :activity, "Starting")
      |> Transcript.update_progress("progress", :activity, "Finished")

    assert List.last(updated.messages).progress == [
             %{item_id: "progress", kind: :activity, content: "Finished"}
           ]

    version_3_snapshot = %{
      "version" => 3,
      "thread_id" => nil,
      "model" => "gpt-5.6-terra",
      "reasoning_effort" => "medium",
      "messages" => [
        %{"id" => 1, "role" => "visitor", "content" => "Hello", "update_count" => 0},
        %{"id" => 2, "role" => "assistant", "content" => "Answer", "update_count" => 1}
      ],
      "pending_turn" => nil
    }

    assert {:ok, restored} = Transcript.restore(version_3_snapshot)
    assert List.last(restored.messages).progress == []

    assert Transcript.restore(%{version_3_snapshot | "messages" => [:invalid]}) == :error

    invalid_progress_snapshot = %{
      "version" => 4,
      "thread_id" => nil,
      "model" => "gpt-5.6-terra",
      "reasoning_effort" => "medium",
      "messages" => [
        %{
          "id" => 1,
          "role" => "visitor",
          "content" => "Hello",
          "update_count" => 0,
          "active_item_id" => 123,
          "progress" => "invalid"
        },
        %{
          "id" => 2,
          "role" => "assistant",
          "content" => "Answer",
          "update_count" => 1,
          "active_item_id" => nil,
          "progress" => []
        }
      ],
      "pending_turn" => nil
    }

    assert Transcript.restore(invalid_progress_snapshot) == :error
  end

  test "checkpoints an active chat before a transport supplies a thread ID" do
    {:ok, busy_chat} = Transcript.submit(Transcript.new(), "Hello")

    assert {:ok,
            %{
              "version" => 4,
              "pending_turn" => %{
                "assistant_message_id" => 2,
                "continuation_attempted" => false,
                "prompt" => "Hello"
              }
            }} = Transcript.snapshot(busy_chat)

    assert {:ok, %{"thread_id" => nil, "messages" => messages}} =
             Transcript.snapshot(Transcript.complete(busy_chat))

    assert Enum.map(messages, & &1["role"]) == ["visitor", "assistant"]
  end

  test "continues an interrupted turn once without duplicating the recovery request" do
    assert {:error, :none} = Transcript.continuation_prompt(Transcript.new())

    {:ok, chat} = Transcript.submit(Transcript.new(), "Hello")

    assert {:ok, "Hello", recovered} = Transcript.continuation_prompt(chat)
    assert recovered.pending_turn.continuation_attempted == true
    assert {:error, :already_attempted} = Transcript.continuation_prompt(recovered)

    resumed = %{
      recovered
      | thread_id: "thread-1",
        pending_turn: %{recovered.pending_turn | continuation_attempted: false}
    }

    assert {:ok, prompt, _recovered} = Transcript.continuation_prompt(resumed)
    assert prompt =~ "Continue the previous answer"
  end

  test "changes models only between turns" do
    chat = Transcript.new()
    assert Transcript.new("gpt-5.6-luna").reasoning_effort == "medium"

    assert {:ok, selected} = Transcript.select_model(chat, "gpt-5.6-luna", "medium")
    assert selected.model == "gpt-5.6-luna"
    assert selected.reasoning_effort == "medium"

    {:ok, busy} = Transcript.submit(selected, "Hello")
    assert Transcript.select_model(busy, "gpt-5.6-sol", "low") == {:error, busy}
    assert Transcript.select_model(chat, "", "medium") == {:error, chat}
    assert Transcript.select_model(chat, "gpt-5.6-luna", "impossible") == {:error, chat}
  end

  test "enforces a role-required model even while a restored turn is active" do
    {:ok, busy} = Transcript.submit(Transcript.new("gpt-5.6-terra", "high"), "Continue")

    restricted = Transcript.enforce_model(busy, "gpt-5.6-luna", "medium")

    assert restricted.model == "gpt-5.6-luna"
    assert restricted.reasoning_effort == "medium"
    assert restricted.busy
    assert restricted.pending_turn == busy.pending_turn
  end

  test "snapshots the selected model and effort" do
    chat = Transcript.new("gpt-5.6-luna", "medium")

    assert {:ok,
            %{
              "version" => 4,
              "model" => "gpt-5.6-luna",
              "reasoning_effort" => "medium"
            }} = Transcript.snapshot(chat)

    assert Transcript.snapshot(%{chat | model: ""}) == :error
    assert Transcript.snapshot(%{chat | thread_id: 123}) == :error
    assert Transcript.snapshot(%{chat | busy: true}) == :error
    assert Transcript.snapshot(:invalid) == :error
  end

  test "restores an empty versioned snapshot" do
    assert Transcript.restore(%{"version" => 1, "thread_id" => nil, "messages" => []}) ==
             {:ok, Transcript.new()}
  end

  test "rejects malformed and unsupported snapshots" do
    assert Transcript.restore(%{}) == :error

    assert Transcript.restore(%{
             "version" => 1,
             "thread_id" => 123,
             "messages" => []
           }) == :error

    assert Transcript.restore(%{
             "version" => 1,
             "thread_id" => "thread-1",
             "messages" => [%{"id" => 1, "role" => "visitor"}]
           }) == :error

    assert Transcript.restore(%{
             "version" => 2,
             "thread_id" => nil,
             "model" => 123,
             "reasoning_effort" => "medium",
             "messages" => []
           }) == :error

    assert Transcript.restore(%{
             "version" => 2,
             "thread_id" => nil,
             "model" => "gpt-5.6-luna",
             "reasoning_effort" => "impossible",
             "messages" => []
           }) == :error

    assert Transcript.restore(%{
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

    assert Transcript.restore(%{
             "version" => 4,
             "thread_id" => nil,
             "model" => "gpt-5.6-luna",
             "reasoning_effort" => "medium",
             "messages" => [
               %{
                 "id" => 1,
                 "role" => "visitor",
                 "content" => "Hello",
                 "update_count" => 0,
                 "active_item_id" => nil,
                 "progress" => []
               },
               %{
                 "id" => 2,
                 "role" => "assistant",
                 "content" => "Answer",
                 "update_count" => 1,
                 "active_item_id" => "answer",
                 "progress" => [%{"item_id" => "x", "kind" => "unknown", "content" => "Nope"}]
               }
             ],
             "pending_turn" => nil
           }) == :error

    assert Transcript.restore(%{
             "version" => 3,
             "thread_id" => nil,
             "model" => "gpt-5.6-luna",
             "reasoning_effort" => "medium",
             "messages" => [],
             "pending_turn" => %{"prompt" => "Hello"}
           }) == :error
  end

  test "rejects an interrupted snapshot whose assistant checkpoint is stale" do
    {:ok, chat} = Transcript.submit(Transcript.new(), "Hello")
    {:ok, snapshot} = Transcript.snapshot(chat)

    stale = put_in(snapshot, ["pending_turn", "assistant_message_id"], 3)

    assert Transcript.restore(stale) == :error
  end
end
