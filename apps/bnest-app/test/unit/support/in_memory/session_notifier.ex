defmodule BnestApp.Test.InMemory.SessionNotifier do
  @moduledoc """
  A recording `BnestApp.Identity.Ports.SessionNotifier`. Logout runs in the caller's
  process, so each disconnect is sent to that process as
  `{:session_disconnected, session_digest}` for the test to assert.
  """

  @behaviour BnestApp.Identity.Ports.SessionNotifier

  @impl true
  def disconnect(session_digest) do
    send(self(), {:session_disconnected, session_digest})
    :ok
  end
end
