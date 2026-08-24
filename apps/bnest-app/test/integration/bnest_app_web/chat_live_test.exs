defmodule BnestAppWeb.ChatLiveTest do
  use BnestAppWeb.ConnCase, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BnestApp.Chat

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

  test "falls back to Terra when a saved model is no longer available", %{conn: conn} do
    snapshot = %{
      "version" => 2,
      "thread_id" => nil,
      "model" => "removed-model",
      "reasoning_effort" => "medium",
      "messages" => []
    }

    conn = put_connect_params(conn, %{"chat" => Jason.encode!(snapshot)})
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             "[data-role=model-selector] option[value='gpt-5.6-terra'][selected]"
           )
  end

  test "does not persist a completed turn until Codex supplies a thread ID" do
    {:ok, chat} = Chat.submit(Chat.new(), "Hello")

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, chat: chat, codex_session: :current}
    }

    assert {:noreply, result} =
             BnestAppWeb.ChatLive.handle_info({:codex, :current, :turn_completed}, socket)

    assert result.assigns.chat.busy == false
  end
end
