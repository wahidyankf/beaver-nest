defmodule BnestAppWeb.UserSocket do
  @moduledoc """
  The Absinthe GraphQL subscription socket at `/api/graphql/socket`. Identity is
  resolved only from the server-decoded session carried in `connect_info`
  (the same cookie/session configuration as HTTP); socket params are never
  trusted for identity, role, or authorization (tech-doc 008).

  The Absinthe context is the one the HTTP pipeline builds for the same browser
  session: the session's user, and the digest of that browser's own session token,
  which `BnestAppWeb.UserAuth.fetch_current_user/2` stores beside the user. A session
  cookie written before the digest was stored (a browser still connected across the
  deploy that started storing it) carries none, so its socket keeps reconnecting with no
  digest rather than an invented one; its next HTTP request stores it.

  A digest the session carries is re-checked against the Identity store at
  connect time: logout revokes the server-side record while the signed cookie
  still exists, and a replayed post-logout session must not connect. The
  socket's ID names that digest (`"identity:<digest>"`), so logout's broadcast
  on the same topic disconnects the live socket; a digest-less (legacy) socket
  keeps no ID, as before.
  """

  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: BnestAppWeb.Schema

  alias BnestApp.Identity

  @impl Phoenix.Socket
  def connect(_params, socket, connect_info) do
    case connect_info do
      %{session: %{"current_user" => %{"userId" => user_id} = user} = session}
      when is_binary(user_id) ->
        digest = session_digest(session)

        if is_nil(digest) or Identity.session_active?(digest) do
          context = %{current_user: user, session_digest: digest}
          {:ok, Absinthe.Phoenix.Socket.put_options(socket, context: context)}
        else
          :error
        end

      _unauthenticated ->
        :error
    end
  end

  @impl Phoenix.Socket
  def id(socket) do
    case socket do
      %{assigns: %{absinthe: %{opts: opts}}} when is_list(opts) ->
        case Keyword.get(opts, :context) do
          %{session_digest: digest} when is_binary(digest) -> "identity:" <> digest
          _without_digest -> nil
        end

      _socket_without_absinthe_context ->
        nil
    end
  end

  defp session_digest(%{"session_digest" => digest}) when is_binary(digest), do: digest
  defp session_digest(_session_without_digest), do: nil
end
