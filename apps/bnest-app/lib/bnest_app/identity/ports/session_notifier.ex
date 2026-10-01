defmodule BnestApp.Identity.Ports.SessionNotifier do
  @moduledoc """
  Tells every live connection of one browser session that the session ended, so it
  disconnects. The session is named by its token digest, never by the token.
  """

  @callback disconnect(session_digest :: String.t()) :: :ok
end
