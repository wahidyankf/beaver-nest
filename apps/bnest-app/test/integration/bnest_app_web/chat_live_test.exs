defmodule BnestAppWeb.ChatLiveTest do
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BnestApp.CodexChat.Adapters.CodexPortSession
  alias BnestApp.CodexChat.Domain.Transcript

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
