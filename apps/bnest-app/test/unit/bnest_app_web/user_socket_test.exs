defmodule BnestAppWeb.UserSocketTest do
  # Not async: connects re-check the session digest against the Identity store
  # over Storage's records, which are application-wide, and the revocation
  # scenarios share the one store handle.
  use ExUnit.Case, async: false

  alias BnestApp.Identity
  alias BnestApp.Identity.Domain.Session
  alias BnestApp.Identity.Sessions
  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestAppWeb.UserSocket

  # What the HTTP pipeline writes into the signed session for a logged-in browser: the
  # resolved account and the digest of that browser's own session token.
  @user %{
    "userId" => "test-user-socket-member",
    "displayUsername" => "test-user-socket-member-display",
    "roles" => ["children"]
  }

  setup do
    previous = StoragePorts.install()
    on_exit(fn -> StoragePorts.restore(previous) end)
    records = InMemoryRecordBackend.start()
    start_supervised!({Records, store: records})

    store = Identity.adapter(:identity_store).new(BnestApp.Storage.active_store())
    {:ok, token} = Sessions.create(store, @user["userId"])

    %{store: store, token: token, digest: Session.digest(token), user: @user}
  end

  defp connect(params, session) do
    UserSocket.connect(params, %Phoenix.Socket{endpoint: BnestAppWeb.Endpoint}, %{
      session: session
    })
  end

  defp absinthe_context({:ok, %Phoenix.Socket{assigns: %{absinthe: %{opts: opts}}}}),
    do: Keyword.fetch!(opts, :context)

  test "the socket context is the session's own user and session digest", %{
    user: user,
    digest: digest
  } do
    session = %{"current_user" => user, "session_digest" => digest}
    spoofed = %{"userId" => "test-user-socket-spoofed", "role" => "admin"}

    assert %{current_user: ^user, session_digest: ^digest} =
             absinthe_context(connect(spoofed, session))
  end

  test "the session digest is the session's, never one derived from the user ID", %{
    user: user,
    digest: digest
  } do
    session = %{"current_user" => user, "session_digest" => digest}
    user_id_digest = :crypto.hash(:sha256, user["userId"]) |> Base.encode16(case: :lower)

    refute absinthe_context(connect(%{}, session)).session_digest == user_id_digest
  end

  # A session cookie written before the digest was carried (for example
  # one still connected across a deploy) keeps reconnecting: the user still comes from the
  # session, and the context carries no digest rather than an invented one.
  test "a session written without a digest connects with none", %{user: user} do
    assert %{current_user: ^user, session_digest: nil} =
             absinthe_context(connect(%{}, %{"current_user" => user}))
  end

  test "a connection with no session user is refused" do
    assert connect(%{"userId" => "test-user-socket-spoofed"}, %{}) == :error
    assert connect(%{}, nil) == :error
  end

  # Logout revokes the server-side record while the signed cookie still exists;
  # replaying that session map must not connect.
  test "a revoked session digest does not connect", %{store: store, token: token, user: user} do
    digest = Session.digest(token)
    assert Identity.session_active?(digest)

    assert Sessions.revoke(store, token) == {:ok, digest}
    refute Identity.session_active?(digest)

    assert connect(%{}, %{"current_user" => user, "session_digest" => digest}) == :error
  end

  test "an unknown session digest does not connect", %{user: user} do
    digest = Session.digest("test-user-socket-never-issued")
    refute Identity.session_active?(digest)

    assert connect(%{}, %{"current_user" => user, "session_digest" => digest}) == :error
  end

  test "the socket id names the digest, so logout's broadcast disconnects it", %{
    user: user,
    digest: digest
  } do
    {:ok, socket} = connect(%{}, %{"current_user" => user, "session_digest" => digest})

    assert UserSocket.id(socket) == "identity:" <> digest
  end

  test "a digest-less socket keeps no id", %{user: user} do
    {:ok, socket} = connect(%{}, %{"current_user" => user})

    assert UserSocket.id(socket) == nil
  end
end
