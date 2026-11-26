defmodule BnestApp.CodexChat.ConversationsFacadeTest do
  use ExUnit.Case, async: true

  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.Conversations
  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.Test.InMemory.TranscriptStore, as: InMemoryTranscriptStore

  @owner "test-user-codex-conversations-facade"
  @now ~U[2026-10-01 08:30:15.123456Z]
  @second ~U[2026-10-01 08:30:15Z]

  # A transcript store whose every write fails for a reason other than a stale revision.
  defmodule BrokenStore do
    @moduledoc false
    @behaviour BnestApp.CodexChat.Ports.TranscriptStore

    @impl true
    def new, do: %{adapter: __MODULE__}

    @impl true
    def read(_store, _owner_id), do: {:error, :missing}

    @impl true
    def write(_store, _owner_id, _expected_revision, _record), do: {:error, :write_failed}
  end

  setup do
    %{store: InMemoryTranscriptStore.start()}
  end

  test "saving and loading round-trips every conversation", %{store: store} do
    {:ok, chat} = Transcript.submit(Transcript.new(), "Hello")

    {:ok, state} =
      Conversations.new(id: "chat-1", now: @second)
      |> Conversations.put_transcript("chat-1", chat, now: @second)

    {:ok, renamed} = Conversations.rename(state, "chat-1", "Hello", now: @second)
    {:ok, _id, state} = Conversations.create(renamed, id: "chat-2", now: @second)

    assert {:ok, record} =
             CodexChat.save_conversations(@owner, state, nil, store: store, now: @now)

    assert record["recordType"] == "chat"
    assert record["ownerId"] == @owner

    assert {:ok, loaded, ^record} = CodexChat.load_conversations(@owner, store: store)
    assert Conversations.list(loaded) == Conversations.list(state)

    assert {:ok, first} = Conversations.select(loaded, "chat-1")
    assert {:ok, %{title: "Hello", transcript: transcript}} = Conversations.selected(first)
    assert transcript.messages == chat.messages
  end

  test "loading wraps a legacy single-transcript record into one conversation", %{store: store} do
    {:ok, chat} = Transcript.submit(Transcript.new(), "Legacy topic")
    {:ok, snapshot} = Transcript.snapshot(chat)
    {:ok, legacy} = CodexChat.save_transcript(@owner, chat, nil, store: store, now: @now)
    assert legacy["state"] == snapshot

    assert {:ok, loaded, ^legacy} = CodexChat.load_conversations(@owner, store: store)
    assert [%{title: "Legacy topic"}] = Conversations.list(loaded)

    assert {:ok, %{transcript: transcript}} = Conversations.selected(loaded)
    assert transcript.messages == chat.messages
  end

  test "loading reports a missing or unrestorable chat", %{store: store} do
    assert CodexChat.load_conversations(@owner, store: store) == {:error, :missing}

    {:ok, _record} =
      InMemoryTranscriptStore.write(store, @owner, nil, %{"state" => %{"version" => 0}})

    assert CodexChat.load_conversations(@owner, store: store) == {:error, :unrestorable}
  end

  test "a stale write keeps the newer stored state and fails the selected transcript", %{
    store: store
  } do
    {:ok, read_earlier} =
      CodexChat.save_conversations(@owner, Conversations.new(id: "chat-1", now: @now), nil,
        store: store
      )

    {:ok, current} =
      CodexChat.save_conversations(
        @owner,
        Conversations.new(id: "chat-1", now: @now),
        read_earlier,
        store: store
      )

    {:ok, chat} = Transcript.submit(Transcript.new(), "Hello")

    {:ok, stale} =
      Conversations.new(id: "chat-1", now: @now)
      |> Conversations.put_transcript("chat-1", chat, now: @now)

    assert {:error, failed} =
             CodexChat.save_conversations(@owner, stale, read_earlier, store: store)

    assert {:ok, %{transcript: transcript}} = Conversations.selected(failed)
    assert transcript.error == "Newer chat data exists. Reload before continuing."
    assert InMemoryTranscriptStore.read(store, @owner) == {:ok, current}
  end

  test "a refused write fails the selected transcript and keeps the saved chat", %{store: store} do
    state = Conversations.new(id: "chat-1", now: @now)

    assert {:error, failed} =
             CodexChat.save_conversations(@owner, state, nil,
               store: BrokenStore.new(),
               now: @now
             )

    assert {:ok, %{transcript: transcript}} = Conversations.selected(failed)

    assert transcript.error ==
             "Chat could not be saved. Your previous saved chat is unchanged."

    assert InMemoryTranscriptStore.snapshot(store) == %{}
  end

  test "saves nothing for conversations without a valid snapshot", %{store: store} do
    assert CodexChat.save_conversations(@owner, %{selected_id: nil, conversations: %{}}, nil,
             store: store
           ) ==
             :error

    assert InMemoryTranscriptStore.snapshot(store) == %{}
  end

  test "listing, creating, selecting, deleting and renaming delegate to the domain" do
    state = Conversations.new(id: "chat-1", now: @now)

    assert [%{id: "chat-1", title: "New chat"}] = CodexChat.list_conversations(state)

    assert {:ok, "chat-2", created} =
             CodexChat.create_conversation(state, id: "chat-2", now: @now)

    assert {:ok, selected} = CodexChat.select_conversation(created, "chat-1")
    assert {:ok, %{id: "chat-1"}} = CodexChat.selected_conversation(selected)

    assert {:ok, renamed} =
             CodexChat.rename_conversation(selected, "chat-1", "Renamed", now: @now)

    assert {:ok, %{title: "Renamed"}} = CodexChat.selected_conversation(renamed)

    assert {:ok, deleted} = CodexChat.delete_conversation(renamed, "chat-2")
    assert [%{id: "chat-1"}] = CodexChat.list_conversations(deleted)

    assert CodexChat.select_conversation(deleted, "missing") == {:error, :unknown_conversation}
    assert CodexChat.rename_conversation(deleted, "chat-1", "  ") == {:error, :invalid_title}

    assert CodexChat.default_conversation_title("  Padded topic  ") == "Padded topic"
    assert CodexChat.default_conversation_title("   ") == "New chat"
  end

  test "put_conversation_transcript stores the selected transcript" do
    {:ok, chat} = Transcript.submit(Transcript.new(), "Hello")
    state = Conversations.new(id: "chat-1", now: @now)

    assert {:ok, stored} = CodexChat.put_conversation_transcript(state, "chat-1", chat, now: @now)
    assert {:ok, %{transcript: ^chat}} = CodexChat.selected_conversation(stored)

    assert CodexChat.put_conversation_transcript(state, "missing", chat) ==
             {:error, :unknown_conversation}
  end
end
