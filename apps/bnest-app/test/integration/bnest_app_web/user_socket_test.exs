defmodule BnestAppWeb.UserSocketSessionTest do
  @moduledoc """
  The GraphQL subscription socket's identity, from the session the HTTP pipeline wrote.

  A real request through the endpoint writes the signed session; the socket is then
  connected through `Phoenix.ChannelTest` with exactly that session as its
  `connect_info`, as the endpoint's `connect_info: [session: ...]` decodes it from the
  cookie.
  """
  use BnestAppWeb.ConnCase, async: false

  require Phoenix.ChannelTest

  alias BnestApp.Identity

  # The signed session a request through the endpoint leaves for the browser.
  defp session_after_request(conn) do
    conn
    |> get("/")
    |> get_session()
  end

  defp identity_token(conn), do: Plug.Conn.fetch_cookies(conn).cookies["_bnest_identity"]

  defp socket_context(session) do
    {:ok, socket} =
      Phoenix.ChannelTest.connect(BnestAppWeb.UserSocket, %{}, connect_info: %{session: session})

    Keyword.fetch!(socket.assigns.absinthe.opts, :context)
  end

  test "a logged-in request stores the session's digest beside its user", %{conn: conn} do
    session = session_after_request(conn)

    assert session["session_digest"] == Identity.session_digest(identity_token(conn))
    assert %{"userId" => _user_id} = session["current_user"]
  end

  test "the socket carries the HTTP session's digest, not one derived from the user ID",
       %{conn: conn} do
    session = session_after_request(conn)
    context = socket_context(session)
    user_id = session["current_user"]["userId"]

    assert context.current_user == session["current_user"]
    assert context.session_digest == Identity.session_digest(identity_token(conn))

    refute context.session_digest ==
             :crypto.hash(:sha256, user_id) |> Base.encode16(case: :lower)
  end

  test "a request with no identity clears a digest left in the session", %{conn: conn} do
    stale = conn |> get("/") |> recycle() |> delete_req_cookie("_bnest_identity")

    refute Map.has_key?(session_after_request(stale), "session_digest")
  end
end
