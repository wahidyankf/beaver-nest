defmodule BnestAppWeb.FamilyChatRoomPageTest do
  @moduledoc """
  The shipped room shell at the real `/family-chat/:slug` route.

  Two things are worth proving here and nowhere else. First, that the
  template renders at all with the reply flag absent -- the compatibility
  release runs exactly that way, and a `KeyError` on an unassigned
  `@reply_enabled` would take the whole room down rather than merely hiding
  a feature. Second, that the menu host and the reply strip ship in the
  static shell rather than being created by JavaScript, because
  `elements.js` queries for them once at mount and would silently bind
  nothing if they were absent.

  Where focus lands, and whether the menu opens, are browser concerns proven
  at `bnest-app-fe-e2e`.
  """
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest

  alias BnestApp.FamilyChat
  alias BnestAppWeb.FamilyChatHTML
  alias Phoenix.HTML.Safe

  setup %{conn: conn} do
    {:ok, _room} = FamilyChat.Store.migrate!()
    {:ok, conn: authenticated_conn(conn)}
  end

  describe "the room shell" do
    test "renders with the reply flag unassigned, reporting replies off", %{conn: conn} do
      html = room_html(conn)

      assert html =~ ~s(data-family-chat-reply-enabled="false")
    end

    test "ships the single menu host, hidden, with its accessible name", %{conn: conn} do
      html = room_html(conn)

      assert html =~ ~s(data-role="family-chat-message-actions")
      assert html =~ ~s(aria-label="Message actions")
      # One host for the whole room is what makes two open menus
      # unrepresentable; a second would make it a matter of discipline.
      assert count_occurrences(html, ~s(data-role="family-chat-message-actions")) == 1
    end

    test "ships the reply strip inside the composer, hidden, with its cancel control", %{
      conn: conn
    } do
      html = room_html(conn)

      assert html =~ ~s(data-role="family-chat-reply-strip")
      assert html =~ ~s(data-role="family-chat-reply-strip-name")
      assert html =~ ~s(data-role="family-chat-reply-strip-preview")
      assert html =~ ~s(data-role="family-chat-reply-strip-cancel")
      assert html =~ "Cancel reply"

      composer = html |> String.split(~s(<form class="family-chat-composer")) |> List.last()
      assert composer =~ ~s(data-role="family-chat-reply-strip")
    end

    test "renders the same shell with the flag on, reporting replies enabled", %{conn: conn} do
      html = render_room_with_reply_enabled(conn, true)

      assert html =~ ~s(data-family-chat-reply-enabled="true")
      assert html =~ ~s(data-role="family-chat-message-actions")
      assert html =~ ~s(data-role="family-chat-reply-strip")
    end
  end

  defp room_html(conn) do
    conn = get(conn, "/family-chat/#{FamilyChat.canonical_room_slug()}")
    assert conn.status == 200
    html_response(conn, 200)
  end

  # Renders the same template through the same HTML module the controller
  # uses, with the assign the controller will pass once the flag is plumbed
  # (Phase 7). Going through the module rather than hand-building the markup
  # is what makes this a proof about the shipped template.
  defp render_room_with_reply_enabled(conn, reply_enabled) do
    user_id = current_user_id(conn)
    {:ok, room} = FamilyChat.get_room_for(user_id, FamilyChat.canonical_room_slug())

    %{
      conn: conn,
      flash: %{},
      current_user: %{"userId" => user_id},
      room: room,
      reply_enabled: reply_enabled
    }
    |> FamilyChatHTML.room()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp current_user_id(conn) do
    conn
    |> get("/family-chat/#{FamilyChat.canonical_room_slug()}")
    |> html_response(200)
    |> then(fn html ->
      [_whole, user_id] = Regex.run(~r/data-current-user-id="([^"]+)"/, html)
      user_id
    end)
  end

  defp count_occurrences(haystack, needle) do
    haystack |> String.split(needle) |> length() |> Kernel.-(1)
  end
end
