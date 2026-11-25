defmodule BnestAppWeb.FamilyChatRoomPageTest do
  @moduledoc """
  The shipped room shell at the real `/family-chat/:slug` route.

  Two things are worth proving here and nowhere else. First, that the room
  always reports replies enabled -- there is no flag to turn them off, and
  the browser always asks for `replyTo` and always draws the actions control.
  Second, that the menu host and the reply strip ship in the
  static shell rather than being created by JavaScript, because
  `elements.js` queries for them once at mount and would silently bind
  nothing if they were absent.

  Where focus lands, and whether the menu opens, are browser concerns proven
  at `bnest-app-fe-e2e`.
  """
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest

  alias BnestApp.FamilyChat

  setup %{conn: conn} do
    {:ok, _room} = FamilyChat.migrate!()
    {:ok, conn: authenticated_conn(conn)}
  end

  describe "the room shell" do
    test "always reports replies enabled at the route", %{conn: conn} do
      html = room_html(conn)

      assert html =~ ~s(data-family-chat-reply-enabled="true")
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
  end

  defp room_html(conn) do
    conn = get(conn, "/family-chat/#{FamilyChat.canonical_room_slug()}")
    assert conn.status == 200
    html_response(conn, 200)
  end

  defp count_occurrences(haystack, needle) do
    haystack |> String.split(needle) |> length() |> Kernel.-(1)
  end
end
