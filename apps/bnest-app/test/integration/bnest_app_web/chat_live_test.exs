defmodule BnestAppWeb.ChatLiveTest do
  use BnestAppWeb.ConnCase, async: true

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
