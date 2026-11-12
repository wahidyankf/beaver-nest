defmodule BnestAppWeb.ChatLiveTest do
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BnestApp.CodexChat.Adapters.CodexPortSession
  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.Test.CodexReplyPage
  alias BnestAppWeb.ChatComponents

  setup do
    previous = Application.fetch_env!(:bnest_app, :identity_cutover_enabled)
    Application.put_env(:bnest_app, :identity_cutover_enabled, false)
    on_exit(fn -> Application.put_env(:bnest_app, :identity_cutover_enabled, previous) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  test "does not close a session for a disconnected render" do
    assert :ok = BnestAppWeb.ChatLive.terminate(:normal, %{assigns: %{codex_session: nil}})
  end

  test "ignores events from a replaced Codex session" do
    socket = %Phoenix.LiveView.Socket{assigns: %{codex_session: :current}}

    assert {:noreply, ^socket} =
             BnestAppWeb.ChatLive.handle_info(
               {:codex, :stale, {:assistant_update, "ignored"}},
               socket
             )
  end

  test "ignores disconnected model-form recovery" do
    socket = %Phoenix.LiveView.Socket{}

    assert {:noreply, ^socket} =
             BnestAppWeb.ChatLive.handle_event("ignore_model_recovery", %{}, socket)
  end

  test "ignores disconnected effort-form recovery" do
    socket = %Phoenix.LiveView.Socket{}

    assert {:noreply, ^socket} =
             BnestAppWeb.ChatLive.handle_event("ignore_effort_recovery", %{}, socket)
  end

  # phx-auto-recover sends the composer's values when the socket reconnects. An empty composer sends only the event
  # target, so a payload without the prompt must not crash the view (a crash remounts the chat mid-turn).
  test "a recovered draft with no prompt field leaves the chat running", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    assert render_hook(view, "recover_draft", %{"_target" => ["chat", "prompt"]}) =~
             "chat-composer-form"

    assert Process.alive?(view.pid)
  end

  test "ignores an unsupported effort selection" do
    socket = %Phoenix.LiveView.Socket{assigns: %{chat: Transcript.new()}}

    assert {:noreply, ^socket} =
             BnestAppWeb.ChatLive.handle_event(
               "select_effort",
               %{"reasoning_effort" => "impossible"},
               socket
             )
  end

  test "falls back to Terra when a saved model is no longer available", %{conn: conn} do
    snapshot = %{
      "version" => 2,
      "thread_id" => nil,
      "model" => "removed-model",
      "reasoning_effort" => "medium",
      "messages" => []
    }

    conn = put_connect_params(conn, %{"chat" => Jason.encode!(snapshot)})
    {:ok, view, _html} = live(conn, "/chat")

    assert has_element?(
             view,
             "[data-role=model-selector] option[value='gpt-5.6-terra'][selected]"
           )
  end

  test "persists a completed turn before Codex supplies a thread ID" do
    {:ok, chat} = Transcript.submit(Transcript.new(), "Hello")

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        chat: chat,
        central_record: nil,
        codex_session: :current,
        current_user: %{"userId" => "user-test-no-thread-id"}
      }
    }

    assert {:noreply, result} =
             BnestAppWeb.ChatLive.handle_info({:codex, :current, :turn_completed}, socket)

    assert result.assigns.chat.busy == false
    assert result.assigns.central_record["state"]["thread_id"] == nil
  end

  test "replaces a failed resumed Codex session and preserves the transcript" do
    {:ok, restored} =
      Transcript.restore(%{
        "version" => 2,
        "thread_id" => "unavailable-thread",
        "model" => "gpt-5.6-terra",
        "reasoning_effort" => "medium",
        "messages" => [
          %{"id" => 1, "role" => "visitor", "content" => "Original", "update_count" => 0},
          %{"id" => 2, "role" => "assistant", "content" => "Answer", "update_count" => 1}
        ]
      })

    {:ok, chat} = Transcript.submit(restored, "Continue")

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        chat: chat,
        central_record: nil,
        codex_session: :failed_session,
        current_user: %{"userId" => "user-test-resume-fallback"},
        repository_access_mode: :read_only
      }
    }

    assert {:noreply, result} =
             BnestAppWeb.ChatLive.handle_info(
               {:codex, :failed_session, {:resume_failed, "unavailable"}},
               socket
             )

    assert result.assigns.chat.thread_id == nil
    assert result.assigns.chat.busy == false
    assert result.assigns.chat.error =~ "transcript is preserved"

    assert Enum.map(result.assigns.chat.messages, & &1.content) == [
             "Original",
             "Answer",
             "Continue",
             ""
           ]

    assert result.assigns.central_record["ownerId"] == "user-test-resume-fallback"
  end

  test "CodexPortSession classifies a fixture resume failure" do
    use_fixture_runner()

    assert {:ok, session} =
             CodexPortSession.open(
               self(),
               "unavailable-thread",
               "gpt-5.6-terra",
               "medium",
               :read_only
             )

    assert :ok = CodexPortSession.send_prompt(session, "Continue")

    assert_receive {:codex, ^session, {:resume_failed, "Fixture Codex thread is unavailable."}},
                   2_000

    assert :ok = CodexPortSession.close(session)
  end

  test "CodexPortSession forwards public progress with stable runner item IDs" do
    use_fixture_runner()

    assert {:ok, session} =
             CodexPortSession.open(self(), nil, "gpt-5.6-terra", "medium", :read_only)

    assert :ok = CodexPortSession.send_prompt(session, "Show progress")

    assert_receive {:codex, ^session, {:thread_started, _thread_id}}, 2_000

    assert_receive {:codex, ^session,
                    {:reasoning_update, "fixture-reasoning", "Fixture reasoning summary"}},
                   2_000

    assert_receive {:codex, ^session,
                    {:assistant_update, "fixture-progress", "Fixture progress"}},
                   2_000

    assert_receive {:codex, ^session,
                    {:assistant_update, "fixture-final", "Fixture final answer"}},
                   2_000

    assert_receive {:codex, ^session, :turn_completed}, 2_000
    assert :ok = CodexPortSession.close(session)
  end

  test "CodexPortSession refuses a prompt once its runner has exited" do
    use_fixture_runner()

    assert {:ok, session} =
             CodexPortSession.open(self(), "closed-thread", "gpt-5.6-terra", "medium", :read_only)

    monitor = Process.monitor(session)

    assert_receive {:codex, ^session, {:error, "Codex runner exited with status 0."}}, 2_000
    refute_receive {:DOWN, ^monitor, :process, ^session, _reason}, 100
    assert {:error, :closed} = CodexPortSession.send_prompt(session, "Are you there?")
    assert :ok = CodexPortSession.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}
  end

  test "CodexPortSession passes allowlisted repository modes to fresh and resumed runners" do
    use_fixture_runner()

    for {thread_id, mode, expected} <- [
          {nil, :read_only, "Fixture sandbox: read-only"},
          {"fixture-resumed-thread", :workspace_write, "Fixture sandbox: workspace-write"}
        ] do
      assert {:ok, session} =
               CodexPortSession.open(self(), thread_id, "gpt-5.6-terra", "medium", mode)

      assert :ok = CodexPortSession.send_prompt(session, "Report sandbox mode")
      assert_receive {:codex, ^session, {:thread_started, _thread_id}}, 2_000

      assert_receive {:codex, ^session, {:assistant_update, "fixture-sandbox-mode", ^expected}},
                     2_000

      assert_receive {:codex, ^session, :turn_completed}, 2_000
      assert :ok = CodexPortSession.close(session)
    end

    assert {:error, :invalid_repository_mode} =
             CodexPortSession.open(self(), nil, "gpt-5.6-terra", "medium", :danger_full_access)
  end

  test "the production runner loads its SDK after release-style relocation" do
    codex_config = Application.fetch_env!(:bnest_app, :codex)
    runner = CodexPortSession.bundled_runner()
    working_directory = Keyword.fetch!(codex_config, :working_directory)

    relocated_directory =
      Path.join(System.tmp_dir!(), "bnest-codex-runner-#{System.unique_integer([:positive])}")

    File.mkdir_p!(relocated_directory)
    relocated_runner = Path.join(relocated_directory, "chat_runner.mjs")
    File.cp!(runner, relocated_runner)

    # The runner imports its sibling instruction module, so a release-style copy carries both files.
    File.cp!(
      Path.join(Path.dirname(runner), "chat_instructions.mjs"),
      Path.join(relocated_directory, "chat_instructions.mjs")
    )

    on_exit(fn -> File.rm_rf(relocated_directory) end)

    probe =
      """
      process.stdin.push(null);
      process.argv.splice(
        2,
        0,
        #{inspect(working_directory)},
        "gpt-5.6-terra",
        "medium",
        "",
        "read-only",
      );
      await import(process.argv[1]);
      """

    assert {"", 0} =
             System.cmd(
               System.find_executable("node"),
               ["--input-type=module", "--eval", probe, relocated_runner],
               stderr_to_stdout: true
             )
  end

  test "the production runner is located in the packaged application" do
    assert CodexPortSession.bundled_runner() ==
             Application.app_dir(:bnest_app, "priv/codex/chat_runner.mjs")
  end

  test "a single-line visitor message holds exactly its text", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    view
    |> element("#chat-composer-form")
    |> render_submit(%{"chat" => %{"prompt" => "Single line message"}})

    page = view |> render() |> LazyHTML.from_document()

    assert CodexReplyPage.shows_visitor_text?(page, "Single line message")
  end

  # The page renders a Codex reply through the shared `markdown_body/1` markup (ADR 003, Decision 2), so the
  # reply element is exactly what `markdown_body_html/2` produces for the same content and wrapper attributes.
  test "a Codex reply is the shared Markdown component's markup", %{conn: conn} do
    content =
      "Here is **bold** text and a ![Remote logo](https://images.example.test/remote-logo.png)"

    {:ok, view, _html} = live(conn, "/chat")
    submit_visitor_message(view, "Show the shared markup")

    send(view.pid, {:codex, view.pid, {:assistant_update, "shared-markup", content}})
    send(view.pid, {:codex, view.pid, :turn_completed})

    reply = view |> render() |> LazyHTML.from_fragment() |> CodexReplyPage.latest_reply()

    # The wrapper has its id; `phx-update="ignore"` is not compared here, because LiveViewTest applies an
    # ignore only to an element that is not yet on the page (see the note above the streaming test).
    expected =
      ChatComponents.markdown_body_html(content,
        streaming: false,
        attrs: %{
          id: LazyHTML.attribute(reply, "id") |> hd(),
          "data-role": "assistant-message",
          "data-streaming": "false",
          "data-update-count": LazyHTML.attribute(reply, "data-update-count") |> hd()
        }
      )

    assert LazyHTML.to_html(reply) == expected |> LazyHTML.from_fragment() |> LazyHTML.to_html()
    assert CodexReplyPage.contains_element?(reply, "img")
  end

  # ADR 004, Decision 3: the conversation hosts the diagram hook, and each reply has an id, which the
  # browser needs to keep a finished reply (`phx-update="ignore"`) through later patches.
  #
  # Note for the tests below: LiveViewTest applies `phx-update="ignore"` as the server sends it, to an element
  # already on the page, keeping that element's children and non-data attributes. A browser decides from the
  # element already on the page instead, so the patch that ends streaming does add the attribute and the
  # marker. The completed-reply attribute and the marker are therefore checked in the browser suite
  # (bnest-app-fe-e2e), not here.
  @flow_reply "Here is the flow:\n\n```mermaid\nflowchart TD\n  A --> B\n```\n\nIt shows A to B."

  test "the conversation hosts the diagram hook and every reply has an id", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")
    submit_visitor_message(view, "Draw a flow")
    send(view.pid, {:codex, view.pid, {:assistant_update, "flow", @flow_reply}})
    send(view.pid, {:codex, view.pid, :turn_completed})

    page = view |> render() |> LazyHTML.from_fragment()
    assert [conversation] = page |> LazyHTML.query("#chat-conversation") |> Enum.to_list()
    assert LazyHTML.attribute(conversation, "phx-hook") == ["ChatDiagrams"]

    reply = CodexReplyPage.latest_reply(page)
    assert [id] = LazyHTML.attribute(reply, "id")
    assert id =~ ~r/\Aassistant-message-\d+\z/u
  end

  test "a streaming reply carries no ignore attribute and keeps its diagram as source", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/chat")
    submit_visitor_message(view, "Stream a flow")
    send(view.pid, {:codex, view.pid, {:assistant_update, "flow", @flow_reply}})

    streaming = view |> render() |> LazyHTML.from_fragment() |> CodexReplyPage.latest_reply()
    assert CodexReplyPage.streaming?(streaming)
    assert LazyHTML.attribute(streaming, "phx-update") == []
    assert CodexReplyPage.plain_diagram_count(streaming) == 1
    assert CodexReplyPage.marked_diagram_count(streaming) == 0
  end

  # Clear chat restarts the message ids, so a new reply can reuse the id of an earlier reply. The earlier
  # reply must not show in the new conversation. The new diagram's marker is checked in the browser suite.
  test "after Clear chat a new reply that reuses a message id shows only its own text", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/chat")
    submit_visitor_message(view, "First question")

    send(
      view.pid,
      {:codex, view.pid,
       {:assistant_update, "first", "Old reply\n\n```mermaid\nflowchart TD\n  A --> B\n```"}}
    )

    send(view.pid, {:codex, view.pid, :turn_completed})

    first_id =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> CodexReplyPage.latest_reply()
      |> LazyHTML.attribute("id")
      |> hd()

    view |> element("[data-role=clear-chat]") |> render_click()
    submit_visitor_message(view, "Second question")

    send(
      view.pid,
      {:codex, view.pid,
       {:assistant_update, "second", "New reply\n\n```mermaid\nflowchart TD\n  C --> D\n```"}}
    )

    send(view.pid, {:codex, view.pid, :turn_completed})

    reply = view |> render() |> LazyHTML.from_fragment() |> CodexReplyPage.latest_reply()

    assert LazyHTML.attribute(reply, "id") == [first_id]
    assert CodexReplyPage.shows_text?(reply, "New reply")
    assert CodexReplyPage.shows_text?(reply, "C --> D")
    refute CodexReplyPage.shows_text?(reply, "Old reply")
    refute CodexReplyPage.shows_text?(reply, "A --> B")
  end

  # A reconnect during a turn restores the reply as still being written: the page must keep taking its later
  # text, so the answer is not frozen at the part that was saved.
  test "a reply resumed mid-turn takes the rest of its text", %{conn: conn} do
    view = resumed_mid_turn(conn, "Here is the answer so far")

    send(view.pid, {:codex, view.pid, {:assistant_update, "answer", "Here is the full answer."}})

    reply = view |> render() |> LazyHTML.from_fragment() |> CodexReplyPage.latest_reply()
    assert CodexReplyPage.streaming?(reply)
    assert CodexReplyPage.shows_text?(reply, "Here is the full answer.")
    refute CodexReplyPage.shows_text?(reply, "answer so far")
  end

  # A diagram that arrives after a resume is kept as source while the reply streams, as a diagram that
  # arrives in a new turn is.
  test "a diagram that arrives in a resumed reply is kept as source while it streams", %{
    conn: conn
  } do
    view = resumed_mid_turn(conn, "Here is the flow:")

    send(
      view.pid,
      {:codex, view.pid, {:assistant_update, "answer", @flow_reply}}
    )

    reply = view |> render() |> LazyHTML.from_fragment() |> CodexReplyPage.latest_reply()
    assert CodexReplyPage.streaming?(reply)
    assert CodexReplyPage.plain_diagram_count(reply) == 1
    assert CodexReplyPage.marked_diagram_count(reply) == 0
  end

  # A reply that has no text yet shows the placeholder as plain text, never as Markdown.
  test "a Codex reply with no text yet shows the Thinking placeholder as plain text", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/chat")
    submit_visitor_message(view, "Wait for the first part")

    send(view.pid, {:codex, view.pid, {:assistant_update, "placeholder", ""}})

    reply = view |> render() |> LazyHTML.from_fragment() |> CodexReplyPage.latest_reply()

    assert CodexReplyPage.streaming?(reply)
    assert [assistant_id] = LazyHTML.attribute(reply, "id")
    assert assistant_id =~ ~r/\Aassistant-message-\d+\z/u

    # The placeholder is the wrapper's only content: its text, and no element or Markdown paragraph inside it.
    inner =
      reply
      |> LazyHTML.to_html()
      |> String.replace(~r/\A<div[^>]*>/u, "")
      |> String.replace(~r/<\/div>\z/u, "")
      |> String.trim()

    assert inner == "Thinking…"
  end

  # Opens the page on a saved chat whose reply is still being written, as a reconnect does. The fixture
  # session takes the resent prompt, and the test plays Codex by sending the reply's events to the page.
  defp resumed_mid_turn(conn, saved_part) do
    {:ok, chat} = Transcript.submit(Transcript.new(), "Resume the answer")
    chat = Transcript.update_assistant(chat, "answer", saved_part)
    {:ok, snapshot} = Transcript.snapshot(chat)

    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"chat" => Jason.encode!(snapshot)})
      |> live("/chat")

    view
  end

  defp submit_visitor_message(view, prompt) do
    view
    |> element("#chat-composer-form")
    |> render_submit(%{"chat" => %{"prompt" => prompt}})
  end

  defp use_fixture_runner do
    runner = Path.expand("../../support/codex_fixture_runner.mjs", __DIR__)
    previous = System.get_env("BNEST_CODEX_RUNNER")
    System.put_env("BNEST_CODEX_RUNNER", runner)

    on_exit(fn ->
      if previous,
        do: System.put_env("BNEST_CODEX_RUNNER", previous),
        else: System.delete_env("BNEST_CODEX_RUNNER")
    end)
  end
end
