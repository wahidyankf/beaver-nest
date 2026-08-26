defmodule BnestAppWeb.ChatLiveTest do
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BnestApp.Chat
  alias BnestApp.Codex.FixtureSession
  alias BnestApp.Codex.PortSession

  setup do
    previous = Application.fetch_env!(:bnest_app, :identity_cutover_enabled)
    Application.put_env(:bnest_app, :identity_cutover_enabled, false)
    on_exit(fn -> Application.put_env(:bnest_app, :identity_cutover_enabled, previous) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  test "does not close a session for a disconnected render" do
    assert :ok = BnestAppWeb.ChatLive.terminate(:normal, %{assigns: %{session_adapter: nil}})
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
    socket = %Phoenix.LiveView.Socket{assigns: %{chat: Chat.new()}}

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
    {:ok, chat} = Chat.submit(Chat.new(), "Hello")

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
      Chat.restore(%{
        "version" => 2,
        "thread_id" => "unavailable-thread",
        "model" => "gpt-5.6-terra",
        "reasoning_effort" => "medium",
        "messages" => [
          %{"id" => 1, "role" => "visitor", "content" => "Original", "update_count" => 0},
          %{"id" => 2, "role" => "assistant", "content" => "Answer", "update_count" => 1}
        ]
      })

    {:ok, chat} = Chat.submit(restored, "Continue")

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        chat: chat,
        central_record: nil,
        codex_session: :failed_session,
        current_user: %{"userId" => "user-test-resume-fallback"},
        session_adapter: FixtureSession
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

  test "PortSession classifies a fixture resume failure" do
    runner = Path.expand("../../support/codex_fixture_runner.mjs", __DIR__)
    previous = System.get_env("BNEST_CODEX_RUNNER")
    System.put_env("BNEST_CODEX_RUNNER", runner)

    on_exit(fn ->
      if previous,
        do: System.put_env("BNEST_CODEX_RUNNER", previous),
        else: System.delete_env("BNEST_CODEX_RUNNER")
    end)

    assert {:ok, session} =
             PortSession.open(
               self(),
               "unavailable-thread",
               "gpt-5.6-terra",
               "medium"
             )

    assert :ok = PortSession.send_prompt(session, "Continue")

    assert_receive {:codex, ^session, {:resume_failed, "Fixture Codex thread is unavailable."}},
                   2_000

    assert :ok = PortSession.close(session)
  end
end
