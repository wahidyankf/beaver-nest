defmodule BnestApp.Identity.Adapters.EndpointSessionNotifier do
  @moduledoc """
  The `BnestApp.Identity.Ports.SessionNotifier` over the web endpoint. Each live connection
  of a session subscribes to `"identity:<digest>"`, and a `"disconnect"` broadcast on that
  topic closes them.
  """

  @behaviour BnestApp.Identity.Ports.SessionNotifier

  @impl true
  @spec disconnect(String.t()) :: :ok
  def disconnect(session_digest) do
    BnestAppWeb.Endpoint.broadcast("identity:#{session_digest}", "disconnect", %{})
    :ok
  end
end
