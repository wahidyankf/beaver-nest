defmodule BnestAppWeb.UserSocketTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.UserSocket

  # What the HTTP pipeline writes into the signed session for a logged-in browser: the
  # resolved account and the digest of that browser's own session token
  # (`BnestAppWeb.UserAuth.fetch_current_user/2`).
  @user %{
    "userId" => "test-user-socket-member",
    "displayUsername" => "test-user-socket-member-display",
    "roles" => ["children"]
  }
  @session_digest "test-user-socket-session-digest"

  defp connect(params, session) do
    UserSocket.connect(params, %Phoenix.Socket{endpoint: BnestAppWeb.Endpoint}, %{
      session: session
    })
  end

  defp absinthe_context({:ok, %Phoenix.Socket{assigns: %{absinthe: %{opts: opts}}}}),
    do: Keyword.fetch!(opts, :context)

  test "the socket context is the session's own user and session digest" do
    session = %{"current_user" => @user, "session_digest" => @session_digest}
    spoofed = %{"userId" => "test-user-socket-spoofed", "role" => "admin"}

    assert %{current_user: @user, session_digest: @session_digest} =
             absinthe_context(connect(spoofed, session))
  end

  test "the session digest is the session's, never one derived from the user ID" do
    session = %{"current_user" => @user, "session_digest" => @session_digest}
    user_id_digest = :crypto.hash(:sha256, @user["userId"]) |> Base.encode16(case: :lower)

    refute absinthe_context(connect(%{}, session)).session_digest == user_id_digest
  end

  # A browser whose session cookie was written before the digest was carried (for example
  # one still connected across a deploy) keeps reconnecting: the user still comes from the
  # session, and the context carries no digest rather than an invented one.
  test "a session written without a digest connects with none" do
    assert %{current_user: @user, session_digest: nil} =
             absinthe_context(connect(%{}, %{"current_user" => @user}))
  end

  test "a connection with no session user is refused" do
    assert connect(%{"userId" => "test-user-socket-spoofed"}, %{}) == :error
    assert connect(%{}, nil) == :error
  end
end
