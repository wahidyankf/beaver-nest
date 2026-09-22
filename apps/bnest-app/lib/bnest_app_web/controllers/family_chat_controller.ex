defmodule BnestAppWeb.FamilyChatController do
  @moduledoc """
  Plain Phoenix controller (deliberately not a LiveView) for the Family Chat
  room shell, per tech-doc 005. All realtime/outbox/reconnect behavior is
  owned by the browser (`assets/js/family_chat.js` over GraphQL HTTP/socket),
  never by a LiveView `handle_event` command -- the room only ever needs a
  server-rendered shell plus the authenticated identity the browser already
  has from the session (see `test/unit/bnest_app_web/schema_test.exs` and
  this plan's Phase 4 checkpoint: no LiveView chat-command event for family
  chat anywhere in the codebase).
  """

  use BnestAppWeb, :controller

  alias BnestApp.FamilyChat

  @spec redirect_to_canonical(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def redirect_to_canonical(conn, _params) do
    redirect(conn, to: "/family-chat/#{FamilyChat.canonical_room_slug()}")
  end

  @spec room(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def room(conn, %{"slug" => slug}) do
    user_id = conn.assigns.current_user["userId"]

    case FamilyChat.get_room_for(user_id, slug) do
      {:ok, room} ->
        render(conn, :room,
          current_user: conn.assigns.current_user,
          room: room,
          # Read per request rather than at compile time: the experience
          # release flips this on the routed slot without a redeploy.
          reply_enabled: Application.get_env(:bnest_app, :family_chat_reply_enabled, false)
        )

      {:error, _safe_error} ->
        conn |> send_resp(:not_found, "Not found") |> halt()
    end
  end
end
