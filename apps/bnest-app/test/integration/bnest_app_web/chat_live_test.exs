defmodule BnestAppWeb.ChatLiveTest do
  use BnestAppWeb.ConnCase, async: true

  test "does not close a session for a disconnected render" do
    assert :ok = BnestAppWeb.ChatLive.terminate(:normal, %{assigns: %{session_adapter: nil}})
  end
end
