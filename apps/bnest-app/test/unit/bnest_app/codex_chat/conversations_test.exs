defmodule BnestApp.CodexChat.ConversationsTest do
  use ExUnit.Case, async: true

  alias BnestApp.CodexChat.Domain.Conversations
  alias BnestApp.CodexChat.Domain.Transcript

  @now ~U[2026-10-01 08:30:15Z]
  @later ~U[2026-10-01 08:31:15Z]

  test "new starts one selected conversation with the placeholder title" do
    state = Conversations.new(id: "chat-1", now: @now)

    assert {:ok, %{id: "chat-1", title: "New chat", transcript: transcript}} =
             Conversations.selected(state)

    assert transcript == Transcript.new()
    assert [%{id: "chat-1", title: "New chat", updated_at: @now}] = Conversations.list(state)
  end

  test "create selects a new empty conversation and keeps the old one" do
    state = Conversations.new(id: "chat-1", now: @now)

    assert {:ok, "chat-2", created} = Conversations.create(state, id: "chat-2", now: @later)
    assert {:ok, %{id: "chat-2", transcript: transcript}} = Conversations.selected(created)
    assert transcript.messages == []
    assert [first, second] = Conversations.list(created)
    assert first.id == "chat-2"
    assert second.id == "chat-1"
  end

  test "create refuses past the conversation limit" do
    state =
      Enum.reduce(1..49, Conversations.new(id: "chat-1", now: @now), fn n, acc ->
        {:ok, _id, next} = Conversations.create(acc, id: "chat-#{n + 1}", now: @now)
        next
      end)

    assert Conversations.create(state, id: "chat-51", now: @now) == {:error, :too_many}
  end

  test "create without options refuses past the conversation limit" do
    state =
      Enum.reduce(1..49, Conversations.new(id: "chat-1", now: @now), fn n, acc ->
        {:ok, _id, next} = Conversations.create(acc, id: "chat-#{n + 1}", now: @now)
        next
      end)

    assert Conversations.create(state) == {:error, :too_many}
  end

  test "new requires the current time" do
    assert_raise KeyError, fn -> Conversations.new() end
  end

  test "new defaults a blank or non-text title to the placeholder" do
    blank = Conversations.new(id: "chat-1", now: @now, title: "   ")
    assert {:ok, %{title: "New chat"}} = Conversations.selected(blank)

    non_text = Conversations.new(id: "chat-1", now: @now, title: nil)
    assert {:ok, %{title: "New chat"}} = Conversations.selected(non_text)
  end

  test "select switches the selected conversation" do
    state = Conversations.new(id: "chat-1", now: @now)
    {:ok, "chat-2", state} = Conversations.create(state, id: "chat-2", now: @later)

    assert {:ok, selected} = Conversations.select(state, "chat-1")
    assert {:ok, %{id: "chat-1"}} = Conversations.selected(selected)
  end

  test "select refuses an unknown conversation" do
    state = Conversations.new(id: "chat-1", now: @now)

    assert Conversations.select(state, "missing") == {:error, :unknown_conversation}
    assert Conversations.select(state, nil) == {:error, :unknown_conversation}
    assert {:ok, %{id: "chat-1"}} = Conversations.selected(state)
  end

  test "delete removes an unselected conversation and keeps the selection" do
    state = Conversations.new(id: "chat-1", now: @now)
    {:ok, "chat-2", state} = Conversations.create(state, id: "chat-2", now: @later)

    assert {:ok, deleted} = Conversations.delete(state, "chat-1")
    assert [%{id: "chat-2"}] = Conversations.list(deleted)
    assert {:ok, %{id: "chat-2"}} = Conversations.selected(deleted)
  end

  test "delete of the selected conversation falls back to the most recent one" do
    state = Conversations.new(id: "chat-1", now: @now)
    {:ok, "chat-2", state} = Conversations.create(state, id: "chat-2", now: @later)
    {:ok, state} = Conversations.select(state, "chat-1")

    assert {:ok, deleted} = Conversations.delete(state, "chat-1")
    assert {:ok, %{id: "chat-2"}} = Conversations.selected(deleted)
  end

  test "delete of the last conversation reseeds a fresh one" do
    state = Conversations.new(id: "chat-1", now: @now)

    assert {:ok, reseeded} = Conversations.delete(state, "chat-1", id: "chat-2", now: @later)
    assert {:ok, %{id: "chat-2", title: "New chat"}} = Conversations.selected(reseeded)
  end

  test "delete refuses an unknown conversation" do
    state = Conversations.new(id: "chat-1", now: @now)

    assert Conversations.delete(state, "missing") == {:error, :unknown_conversation}
  end

  test "rename trims and caps the title at eighty scalars" do
    state = Conversations.new(id: "chat-1", now: @now)

    assert {:ok, renamed} =
             Conversations.rename(state, "chat-1", "  padded title  ", now: @later)

    assert {:ok, %{title: "padded title", updated_at: @later}} = Conversations.selected(renamed)

    long = String.duplicate("a", 90)

    assert {:ok, capped} = Conversations.rename(renamed, "chat-1", long, now: @later)
    assert {:ok, %{title: title}} = Conversations.selected(capped)
    assert String.length(title) == 80
  end

  test "rename refuses a blank title or an unknown conversation" do
    state = Conversations.new(id: "chat-1", now: @now)

    assert Conversations.rename(state, "chat-1", "   ") == {:error, :invalid_title}
    assert Conversations.rename(state, "chat-1", nil) == {:error, :invalid_title}
    assert Conversations.rename(state, "missing", "Elsewhere") == {:error, :unknown_conversation}
    assert Conversations.rename(state, nil, "Elsewhere") == {:error, :unknown_conversation}
  end

  test "put_transcript stores the transcript and stamps the conversation" do
    state = Conversations.new(id: "chat-1", now: @now)
    {:ok, chat} = Transcript.submit(Transcript.new(), "Hello")

    assert {:ok, stored} = Conversations.put_transcript(state, "chat-1", chat, now: @later)
    assert {:ok, %{transcript: ^chat, updated_at: @later}} = Conversations.selected(stored)
  end

  test "put_transcript refuses an unknown conversation" do
    state = Conversations.new(id: "chat-1", now: @now)

    assert Conversations.put_transcript(state, "missing", Transcript.new()) ==
             {:error, :unknown_conversation}
  end

  test "title_for defaults a blank prompt to the placeholder" do
    assert Conversations.title_for("  ") == "New chat"
    assert Conversations.title_for(nil) == "New chat"
    assert Conversations.title_for("First chat topic") == "First chat topic"
    assert Conversations.title_for("  padded topic  ") == "padded topic"
  end

  test "placeholder_title names the title of a conversation with no user message yet" do
    assert Conversations.placeholder_title() == "New chat"
  end

  test "title_for keeps the first line capped at eighty scalars" do
    assert Conversations.title_for("First line\nSecond line") == "First line"
    assert Conversations.title_for(String.duplicate("b", 90)) == String.duplicate("b", 80)
  end

  test "snapshot restores a round trip including a busy turn" do
    {:ok, chat} = Transcript.submit(Transcript.new(), "Hello")

    {:ok, state} =
      Conversations.new(id: "chat-1", now: @now)
      |> Conversations.put_transcript("chat-1", chat, now: @later)

    {:ok, renamed} = Conversations.rename(state, "chat-1", "Hello", now: @later)
    {:ok, _id, state} = Conversations.create(renamed, id: "chat-2", now: @later)

    assert {:ok, snapshot} = Conversations.snapshot(state)
    assert {:ok, restored} = Conversations.restore(snapshot)
    assert Conversations.list(restored) == Conversations.list(state)

    assert {:ok, busy} = Conversations.select(restored, "chat-1")
    assert {:ok, %{transcript: transcript}} = Conversations.selected(busy)
    assert {:ok, previous} = Conversations.select(state, "chat-1")
    assert {:ok, %{transcript: original}} = Conversations.selected(previous)
    assert transcript.messages == original.messages
    assert transcript.busy == true
  end

  test "restore wraps a legacy single-transcript snapshot into one conversation" do
    {:ok, chat} = Transcript.submit(Transcript.new(), "Legacy topic")
    {:ok, snapshot} = Transcript.snapshot(chat)

    assert {:ok, state} = Conversations.restore(snapshot, @now)
    assert {:ok, %{title: "Legacy topic", transcript: restored}} = Conversations.selected(state)
    assert restored.messages == chat.messages
    assert [%{updated_at: @now}] = Conversations.list(state)
  end

  test "restore gives a legacy transcript without messages the placeholder title" do
    {:ok, snapshot} = Transcript.snapshot(Transcript.new())

    assert {:ok, state} = Conversations.restore(snapshot, @now)
    assert {:ok, %{title: "New chat"}} = Conversations.selected(state)
  end

  test "restore refuses an unknown selection or an unrestorable transcript" do
    {:ok, snapshot} = Conversations.snapshot(Conversations.new(id: "chat-1", now: @now))

    bad_selection = Map.put(snapshot, "selected_id", "missing")
    assert Conversations.restore(bad_selection) == :error

    assert Conversations.restore(%{"version" => 1, "selected_id" => nil, "conversations" => %{}}) ==
             :error

    assert Conversations.restore(%{"version" => 0}) == :error
    assert Conversations.restore(%{"version" => 1}) == :error
  end

  test "snapshot refuses a state that is not a conversation set" do
    assert Conversations.snapshot(nil) == :error
  end

  test "snapshot refuses a conversation with an invalid id" do
    state = Conversations.new(id: "", now: @now)

    assert Conversations.snapshot(state) == :error
  end

  test "snapshot refuses a conversation entry that is not a snapshot" do
    state = Conversations.new(id: "chat-1", now: @now)
    broken = %{state | conversations: %{"chat-1" => :invalid}}

    assert Conversations.snapshot(broken) == :error
  end

  test "restore of a legacy snapshot without the current time is an error" do
    {:ok, snapshot} = Transcript.snapshot(Transcript.new())

    assert Conversations.restore(snapshot) == :error
  end

  test "restore of a legacy snapshot without a version is an error" do
    assert Conversations.restore(%{"messages" => []}, @now) == :error
  end

  test "restore refuses a conversation entry with an invalid title" do
    {:ok, snapshot} = Conversations.snapshot(Conversations.new(id: "chat-1", now: @now))
    bad = put_in(snapshot, ["conversations", "chat-1", "title"], "   ")

    assert Conversations.restore(bad) == :error
  end

  test "restore refuses a conversation entry that is not a map" do
    {:ok, snapshot} = Conversations.snapshot(Conversations.new(id: "chat-1", now: @now))
    bad = put_in(snapshot, ["conversations", "chat-1"], "nope")

    assert Conversations.restore(bad) == :error
  end

  test "restore refuses a conversation id that is not text" do
    {:ok, snapshot} = Conversations.snapshot(Conversations.new(id: "chat-1", now: @now))
    entry = snapshot["conversations"]["chat-1"]
    bad = put_in(snapshot, ["conversations", 123], entry)

    assert Conversations.restore(bad) == :error
  end
end
