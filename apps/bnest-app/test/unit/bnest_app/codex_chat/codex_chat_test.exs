defmodule BnestApp.CodexChat.CodexChatUnitTest do
  # Not async: the configured-adapter tests replace application-wide configuration, start the
  # named record repository and the named model catalog. Every other test passes its own
  # in-memory transcript store and recording agent session.
  use ExUnit.Case, async: false

  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.AgentSession, as: InMemoryAgentSession
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestApp.Test.InMemory.TranscriptStore, as: InMemoryTranscriptStore

  @owner "test-user-codex-chat-unit"
  @now ~U[2026-10-01 08:30:15.123456Z]
  @unavailable "Codex is not available."
  @fresh_conversation "The previous Codex conversation was unavailable. Your transcript is preserved in a fresh conversation."
  @interrupted "The previous response was interrupted. Your transcript is preserved; send a new message to continue."
  @agent [agent_session: InMemoryAgentSession]

  # A transcript store whose every write fails for a reason other than a stale revision.
  defmodule BrokenTranscriptStore do
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

  describe "open_conversation/3" do
    test "opens a new Codex thread in the requested repository mode" do
      transcript = Transcript.new("gpt-5.6-terra", "high")

      assert {:ok, session, ^transcript} =
               CodexChat.open_conversation(transcript, :workspace_write, @agent)

      assert_received {:agent_session, :open, {nil, "gpt-5.6-terra", "high", :workspace_write}}
      assert session.owner == self()
    end

    test "resumes the transcript's Codex thread" do
      transcript = Transcript.put_thread_id(Transcript.new(), "saved-thread")

      assert {:ok, _session, ^transcript} =
               CodexChat.open_conversation(transcript, :read_only, @agent)

      assert_received {:agent_session, :open, {"saved-thread", _model, _effort, :read_only}}
      refute_received {:agent_session, :open, _second}
    end

    test "starts a fresh conversation when the saved thread cannot be resumed" do
      transcript = saved_transcript("unavailable-thread")

      assert {:fresh, _session, fresh} =
               CodexChat.open_conversation(transcript, :read_only, @agent)

      assert fresh == %{transcript | thread_id: nil, error: @fresh_conversation}
      assert_received {:agent_session, :open, {"unavailable-thread", _, _, _}}
      assert_received {:agent_session, :open, {nil, _, _, :read_only}}
    end

    test "reports Codex unavailable when no conversation can be opened" do
      transcript = Transcript.new("unavailable-model", "medium")

      assert CodexChat.open_conversation(transcript, :read_only, @agent) ==
               {:error, Transcript.fail(transcript, @unavailable)}

      stale = Transcript.put_thread_id(transcript, "saved-thread")

      assert CodexChat.open_conversation(stale, :read_only, @agent) ==
               {:error,
                Transcript.fail(
                  %{stale | thread_id: nil, error: @fresh_conversation},
                  @unavailable
                )}
    end
  end

  describe "replace_conversation/4" do
    test "closes the failed session and keeps the transcript in a fresh conversation" do
      {:ok, session, _transcript} =
        CodexChat.open_conversation(Transcript.new(), :read_only, @agent)

      {:ok, transcript} = Transcript.submit(saved_transcript("saved-thread"), "Continue")

      assert {:ok, replacement, fresh} =
               CodexChat.replace_conversation(session, transcript, :workspace_write, @agent)

      assert_received {:agent_session, :close, ^session}
      assert_received {:agent_session, :open, {nil, _, _, :workspace_write}}
      assert replacement != session
      assert fresh == %{Transcript.fail(transcript, @fresh_conversation) | thread_id: nil}
    end

    test "fails the fresh conversation when Codex is unavailable" do
      transcript = Transcript.new("unavailable-model", "medium")
      fresh = %{Transcript.fail(transcript, @fresh_conversation) | thread_id: nil}

      assert CodexChat.replace_conversation(:failed, transcript, :read_only, @agent) ==
               {:error, Transcript.fail(fresh, @unavailable)}
    end
  end

  describe "send_prompt/4 and close/2" do
    test "sends the prompt to the conversation's agent session" do
      {:ok, session, transcript} =
        CodexChat.open_conversation(Transcript.new(), :read_only, @agent)

      assert CodexChat.send_prompt(session, transcript, "Hello", @agent) == {:ok, transcript}
      assert_received {:agent_session, :prompt, ^session, "Hello"}
    end

    test "fails the transcript when the agent session refuses the prompt" do
      {:ok, session, _transcript} =
        CodexChat.open_conversation(Transcript.new(), :read_only, @agent)

      {:ok, transcript} = Transcript.submit(Transcript.new(), "Are you there?")

      assert CodexChat.send_prompt(session, transcript, "Are you there?", @agent) ==
               {:error, Transcript.fail(transcript, @unavailable)}
    end

    test "closes the agent session" do
      {:ok, session, _transcript} =
        CodexChat.open_conversation(Transcript.new(), :read_only, @agent)

      assert CodexChat.close(session, @agent) == :ok
      assert_received {:agent_session, :close, ^session}
    end
  end

  describe "recover_pending_turn/1" do
    test "has nothing to recover without a pending turn" do
      assert CodexChat.recover_pending_turn(Transcript.new()) == :none
    end

    test "resends an interrupted turn once" do
      {:ok, transcript} = Transcript.submit(Transcript.new(), "Hello")

      assert {:resend, "Hello", resent} = CodexChat.recover_pending_turn(transcript)
      assert resent.pending_turn.continuation_attempted
      assert {:interrupted, failed} = CodexChat.recover_pending_turn(resent)
      assert failed == Transcript.fail(resent, @interrupted)
    end
  end

  describe "apply_event/2" do
    setup do
      {:ok, transcript} = Transcript.submit(Transcript.new(), "Hello")
      %{transcript: transcript}
    end

    test "persists a new thread, a completed turn and an error", %{transcript: transcript} do
      assert CodexChat.apply_event(transcript, {:thread_started, "thread-1"}) ==
               {:persist, Transcript.put_thread_id(transcript, "thread-1")}

      assert CodexChat.apply_event(transcript, :turn_completed) ==
               {:persist, Transcript.complete(transcript)}

      assert CodexChat.apply_event(transcript, {:error, "Codex failed."}) ==
               {:persist, Transcript.fail(transcript, "Codex failed.")}
    end

    test "checkpoints streamed answer and progress updates", %{transcript: transcript} do
      assert CodexChat.apply_event(transcript, {:assistant_update, "item-1", "Partial"}) ==
               {:checkpoint, Transcript.update_assistant(transcript, "item-1", "Partial")}

      assert CodexChat.apply_event(transcript, {:assistant_update, "Partial"}) ==
               {:checkpoint, Transcript.update_assistant(transcript, "Partial")}

      assert CodexChat.apply_event(transcript, {:reasoning_update, "item-2", "Thinking"}) ==
               {:checkpoint,
                Transcript.update_progress(transcript, "item-2", :reasoning, "Thinking")}

      assert CodexChat.apply_event(transcript, {:activity_update, "item-3", "Reading"}) ==
               {:checkpoint,
                Transcript.update_progress(transcript, "item-3", :activity, "Reading")}
    end

    test "ignores any other event", %{transcript: transcript} do
      assert CodexChat.apply_event(transcript, {:unknown, "event"}) == :ignore
    end
  end

  describe "save_transcript/4 and load_transcript/2" do
    test "a first save stores a new chat record in its unchanged format", %{store: store} do
      {:ok, transcript} = Transcript.submit(Transcript.new(), "Hello")
      {:ok, snapshot} = Transcript.snapshot(transcript)

      assert {:ok, record} =
               CodexChat.save_transcript(@owner, transcript, nil, store: store, now: @now)

      expected = %{
        "schemaVersion" => 1,
        "recordType" => "chat",
        "ownerId" => @owner,
        "sourceImportId" => nil,
        "state" => snapshot,
        "updatedAt" => "2026-10-01T08:30:15Z",
        "revision" => 0
      }

      assert record == expected
      assert InMemoryTranscriptStore.snapshot(store) == %{@owner => expected}
      assert CodexChat.load_transcript(@owner, store: store) == {:ok, restored(snapshot), record}
    end

    test "replaces the previous record at its revision and keeps its import source",
         %{store: store} do
      {:ok, imported} =
        InMemoryTranscriptStore.write(store, @owner, nil, %{
          "schemaVersion" => 1,
          "recordType" => "chat",
          "ownerId" => @owner,
          "sourceImportId" => "test-import-1",
          "state" => elem(Transcript.snapshot(Transcript.new()), 1),
          "updatedAt" => "2026-09-30T00:00:00Z"
        })

      assert {:ok, record} =
               CodexChat.save_transcript(@owner, Transcript.new(), imported,
                 store: store,
                 now: @now
               )

      assert %{"sourceImportId" => "test-import-1", "revision" => 1} = record
      assert InMemoryTranscriptStore.read(store, @owner) == {:ok, record}
    end

    test "refuses to overwrite a chat that changed after it was read", %{store: store} do
      {:ok, read_earlier} = CodexChat.save_transcript(@owner, Transcript.new(), nil, store: store)

      {:ok, current} =
        CodexChat.save_transcript(@owner, Transcript.new(), read_earlier, store: store)

      {:ok, transcript} = Transcript.submit(Transcript.new(), "Hello")

      assert CodexChat.save_transcript(@owner, transcript, read_earlier, store: store) ==
               {:error,
                Transcript.fail(transcript, "Newer chat data exists. Reload before continuing.")}

      assert InMemoryTranscriptStore.read(store, @owner) == {:ok, current}
    end

    test "reports any other failed save and keeps the saved chat" do
      transcript = Transcript.new()

      assert CodexChat.save_transcript(@owner, transcript, nil,
               store: BrokenTranscriptStore.new()
             ) ==
               {:error,
                Transcript.fail(
                  transcript,
                  "Chat could not be saved. Your previous saved chat is unchanged."
                )}
    end

    test "saves nothing for a transcript without a valid snapshot", %{store: store} do
      assert CodexChat.save_transcript(@owner, %{Transcript.new() | model: ""}, nil, store: store) ==
               :error

      assert InMemoryTranscriptStore.snapshot(store) == %{}
    end

    test "loads nothing when the owner saved no chat or it cannot be restored", %{store: store} do
      assert CodexChat.load_transcript(@owner, store: store) == {:error, :missing}

      {:ok, _record} =
        InMemoryTranscriptStore.write(store, @owner, nil, %{"state" => %{"version" => 0}})

      assert CodexChat.load_transcript(@owner, store: store) == {:error, :unrestorable}
    end
  end

  # Without `store:` and `agent_session:` the facade works on the configured adapters. The
  # unit layer keeps the transcript store record-backed, so it reaches Storage's record
  # repository, started here over an in-memory record backend. The configured agent session
  # is swapped for the recording one, so no Codex runner can start.
  describe "the configured adapters" do
    setup do
      previous = StoragePorts.install()
      on_exit(fn -> StoragePorts.restore(previous) end)
      records = InMemoryRecordBackend.start()
      start_supervised!({Records, store: records})

      config = Application.fetch_env!(:bnest_app, CodexChat)

      Application.put_env(
        :bnest_app,
        CodexChat,
        Keyword.put(config, :agent_session, InMemoryAgentSession)
      )

      on_exit(fn -> Application.put_env(:bnest_app, CodexChat, config) end)
      %{records: records}
    end

    test "keeps the transcript as the :chat record of its owner", %{records: records} do
      {:ok, transcript} = Transcript.submit(Transcript.new(), "Hello")
      {:ok, snapshot} = Transcript.snapshot(transcript)

      assert {:ok, saved} = CodexChat.save_transcript(@owner, transcript, nil, now: @now)

      assert InMemoryRecordBackend.snapshot(records) == %{
               {:chat, @owner} => %{
                 "schemaVersion" => 1,
                 "recordType" => "chat",
                 "ownerId" => @owner,
                 "sourceImportId" => nil,
                 "state" => snapshot,
                 "updatedAt" => "2026-10-01T08:30:15Z",
                 "revision" => 0
               }
             }

      assert CodexChat.load_transcript(@owner) == {:ok, restored(snapshot), saved}
      assert {:ok, %{"revision" => 1}} = CodexChat.save_transcript(@owner, transcript, saved)

      assert CodexChat.save_transcript(@owner, transcript, saved) ==
               {:error,
                Transcript.fail(transcript, "Newer chat data exists. Reload before continuing.")}
    end

    test "opens, prompts and closes through the configured agent session" do
      assert CodexChat.adapter(:agent_session) == InMemoryAgentSession

      {:ok, session, transcript} = CodexChat.open_conversation(Transcript.new(), :read_only)
      assert {:ok, ^transcript} = CodexChat.send_prompt(session, transcript, "Hello")

      assert {:ok, replacement, _fresh} =
               CodexChat.replace_conversation(session, transcript, :read_only)

      assert CodexChat.close(replacement) == :ok

      assert_received {:agent_session, :open, {nil, _, _, :read_only}}
      assert_received {:agent_session, :prompt, ^session, "Hello"}
      assert_received {:agent_session, :close, ^session}
      assert_received {:agent_session, :open, {nil, _, _, :read_only}}
      assert_received {:agent_session, :close, ^replacement}
    end

    test "reads models and model access from the context's model catalog" do
      Enum.each(CodexChat.child_specs(), &start_supervised!/1)
      {:ok, discovered} = CodexChat.adapter(:model_discovery).discover([])

      assert Enum.map(CodexChat.models(), & &1.id) == Enum.map(discovered, & &1.id)

      access = CodexChat.model_access(%{"roles" => ["children"]})
      assert access.model.id == "gpt-5.6-luna"
      refute access.selectable?

      [luna] = access.models
      assert CodexChat.reasoning_effort(luna) == "medium"
      assert CodexChat.reasoning_effort(luna, "ultra") == "medium"
      assert CodexChat.reasoning_effort(luna, "high") == "high"
    end
  end

  # A loaded transcript is the restored snapshot: an answer still streaming when it was saved
  # comes back stopped.
  defp restored(snapshot) do
    {:ok, transcript} = Transcript.restore(snapshot)
    transcript
  end

  defp saved_transcript(thread_id) do
    {:ok, transcript} = Transcript.submit(Transcript.new(), "Remember this transcript")

    transcript
    |> Transcript.update_assistant("Saved response")
    |> Transcript.complete()
    |> Transcript.put_thread_id(thread_id)
  end
end
