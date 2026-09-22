defmodule BnestApp.FamilyChatTest do
  # `async: false`: this module reads the real shared singleton canonical
  # room/tables the ExBdd-generated behaviour tests also share (see
  # `test/unit/support/family_chat_driver.ex`'s cross-scenario pollution
  # notes) -- every case here is read-only against that shared state, but
  # kept synchronous to match the rest of the suite's serialized-access
  # assumption rather than introduce the first concurrent reader of it.
  use ExUnit.Case, async: false

  alias BnestApp.FamilyChat
  alias BnestApp.FamilyChat.Store, as: FamilyChatStore

  setup do
    FamilyChatStore.ensure_ready!()
    :ok
  end

  describe "unauthenticated callers" do
    test "get_room_for/2 rejects a nil user id without touching storage" do
      assert {:error, %{code: "UNAUTHENTICATED", details: nil}} =
               FamilyChat.get_room_for(nil, FamilyChat.canonical_room_slug())
    end

    test "list_messages/3 rejects a nil user id without touching storage" do
      assert {:error, %{code: "UNAUTHENTICATED", details: nil}} =
               FamilyChat.list_messages(nil, FamilyChat.canonical_room_slug(), [])
    end

    test "send_message/4 rejects a nil user id without touching storage" do
      assert {:error, %{code: "UNAUTHENTICATED", details: nil}} =
               FamilyChat.send_message(
                 nil,
                 FamilyChat.canonical_room_slug(),
                 Ecto.UUID.generate(),
                 "hi"
               )
    end

    # `BnestAppWeb.UserSocket.connect/3` itself never reaches this clause (its
    # own `with %{"userId" => _} = user <- session_user(connect_info)` gates
    # on a non-nil user id before ever calling `socket_context_for/1`), so
    # this is the one place `socket_context_for(nil)`'s own documented safe
    # error is exercised directly.
    test "socket_context_for/1 rejects a nil user id" do
      assert {:error, %{code: "UNAUTHENTICATED", details: nil}} =
               FamilyChat.socket_context_for(nil)
    end
  end

  describe "get_room_for/2 slug validation" do
    test "rejects a slug that fails the allowed-character pattern" do
      assert {:error, %{code: "VALIDATION_FAILED", details: nil}} =
               FamilyChat.get_room_for("test-user-family-chat-message-shape", "Not A Valid Slug!")
    end

    test "rejects a non-binary slug" do
      assert {:error, %{code: "VALIDATION_FAILED", details: nil}} =
               FamilyChat.get_room_for("test-user-family-chat-message-shape", 123)
    end

    test "reports a well-formed but nonexistent room as not found" do
      assert {:error, %{code: "ROOM_NOT_FOUND", details: nil}} =
               FamilyChat.get_room_for(
                 "test-user-family-chat-message-shape",
                 "no-such-room-ever-seeded"
               )
    end
  end

  describe "post_system_message/3" do
    test "reports a nonexistent room as not found (resolve_room/1's own lookup)" do
      assert {:error, %{code: "ROOM_NOT_FOUND", details: nil}} =
               FamilyChat.post_system_message(
                 "no-such-room-ever-seeded",
                 "system:test-fixture",
                 "notice"
               )
    end
  end

  describe "send_message/4 posting gate" do
    test "rejects posting while the room has member posting disabled" do
      user = "test-user-family-chat-posting-disabled-" <> Ecto.UUID.generate()
      slug = FamilyChat.canonical_room_slug()

      # Direct raw-SQL toggle of the singleton canonical room (mirrors
      # `BnestApp.FamilyChat.Store`'s own no-Ecto-schema convention); this
      # module runs `async: false` so no sibling test can observe the window,
      # and `on_exit/1` restores it unconditionally so a failed assertion can
      # never leave posting disabled for every later scenario in the shared
      # test database.
      BnestApp.SqliteRepo.query!(
        "UPDATE family_chat_rooms SET member_posting_enabled = 0 WHERE slug = ?",
        [slug]
      )

      on_exit(fn ->
        BnestApp.SqliteRepo.query!(
          "UPDATE family_chat_rooms SET member_posting_enabled = 1 WHERE slug = ?",
          [slug]
        )
      end)

      assert {:error, %{code: "FORBIDDEN", details: nil}} =
               FamilyChat.send_message(user, slug, Ecto.UUID.generate(), "should be forbidden")
    end
  end

  describe "replying" do
    setup do
      room = FamilyChatStore.get_active_room_by_slug(FamilyChat.canonical_room_slug())
      sender = "test-user-family-chat-reply-" <> Ecto.UUID.generate()
      {:ok, room: room, sender: sender}
    end

    test "a commit carries its reply target and resolves the quote", %{room: room, sender: sender} do
      {:ok, original} = commit(room, sender, "Nanti aku jemput jam 5")

      {:ok, reply} =
        FamilyChat.send_message(
          sender,
          FamilyChat.canonical_room_slug(),
          Ecto.UUID.generate(),
          "Oke, aku siapin",
          "Bunda",
          original.id
        )

      assert reply.reply_to_message_id == original.id
      assert reply.reply_to.id == original.id
      assert reply.reply_to.body_preview == "Nanti aku jemput jam 5"
      assert reply.reply_to.sender_kind == "user"
    end

    test "a message sent with no target has no quote", %{room: room, sender: sender} do
      {:ok, message} = commit(room, sender, "Dinner is ready")

      assert message.reply_to_message_id == nil
      assert message.reply_to == nil
    end

    test "the preview collapses whitespace and cuts at 160 graphemes", %{
      room: room,
      sender: sender
    } do
      long = String.duplicate("a", 400)
      {:ok, original} = commit(room, sender, long)
      {:ok, reply} = reply_to(sender, original.id, "answer")

      assert String.length(reply.reply_to.body_preview) == 161
      assert String.ends_with?(reply.reply_to.body_preview, "…")
    end

    test "a short body is previewed whole, with no ellipsis", %{room: room, sender: sender} do
      {:ok, original} = commit(room, sender, "short enough")
      {:ok, reply} = reply_to(sender, original.id, "answer")

      assert reply.reply_to.body_preview == "short enough"
      refute String.ends_with?(reply.reply_to.body_preview, "…")
    end

    test "newlines and runs of whitespace collapse to single spaces", %{
      room: room,
      sender: sender
    } do
      {:ok, original} = commit(room, sender, "first line\n\n  second     line")
      {:ok, reply} = reply_to(sender, original.id, "answer")

      assert reply.reply_to.body_preview == "first line second line"
    end

    test "a target no message has is refused, and nothing commits", %{sender: sender} do
      client_message_id = Ecto.UUID.generate()

      assert {:error, %{code: "VALIDATION_FAILED"}} =
               FamilyChat.send_message(
                 sender,
                 FamilyChat.canonical_room_slug(),
                 client_message_id,
                 "answer",
                 "Bunda",
                 999_999_999
               )

      assert FamilyChatStore.find_message(1, "user", sender, client_message_id) == nil
    end

    test "a non-integer target is refused", %{sender: sender} do
      assert {:error, %{code: "VALIDATION_FAILED"}} =
               FamilyChat.send_message(
                 sender,
                 FamilyChat.canonical_room_slug(),
                 Ecto.UUID.generate(),
                 "answer",
                 "Bunda",
                 "not-a-number"
               )
    end

    test "replaying a client message ID with a different target returns the first commit", %{
      room: room,
      sender: sender
    } do
      {:ok, first_target} = commit(room, sender, "first target")
      {:ok, second_target} = commit(room, sender, "second target")

      client_message_id = Ecto.UUID.generate()

      {:ok, first} =
        FamilyChat.send_message(
          sender,
          FamilyChat.canonical_room_slug(),
          client_message_id,
          "answer",
          "Bunda",
          first_target.id
        )

      {:ok, replayed} =
        FamilyChat.send_message(
          sender,
          FamilyChat.canonical_room_slug(),
          client_message_id,
          "a different answer",
          "Bunda",
          second_target.id
        )

      assert replayed.id == first.id
      assert replayed.reply_to_message_id == first_target.id
      assert replayed.reply_to.id == first_target.id
    end

    test "a page with no replies resolves no quotes at all", %{room: room} do
      assert FamilyChatStore.quotes_for(room.id, []) == %{}
      assert FamilyChatStore.quotes_for(room.id, [%{reply_to_message_id: nil}]) == %{}
    end

    test "a page resolves every distinct target in one lookup", %{room: room, sender: sender} do
      {:ok, a} = commit(room, sender, "target a")
      {:ok, b} = commit(room, sender, "target b")

      quotes =
        FamilyChatStore.quotes_for(room.id, [
          %{reply_to_message_id: a.id},
          %{reply_to_message_id: b.id},
          %{reply_to_message_id: a.id},
          %{reply_to_message_id: nil}
        ])

      assert map_size(quotes) == 2
      assert quotes[a.id].body == "target a"
      assert quotes[b.id].body == "target b"
    end

    # Doubly unreachable, and the second reason was found by trying: the
    # BEFORE DELETE trigger refuses every delete, and `PRAGMA foreign_keys` is
    # on for pooled connections, so `insert_message!/7` cannot even write a
    # dangling reference -- the attempt raises FOREIGN KEY constraint failed.
    #
    # What is still reachable is a raw connection with the pragma off, which is
    # SQLite's own default. So the read path is pinned directly, on the exact
    # input such a row would produce: a target id no message has. Setting it up
    # by deleting, or by inserting a real dangling row, is impossible here and
    # would pass for the wrong reason if it ever stopped being impossible.
    test "a target no row matches resolves to no quote rather than raising", %{room: room} do
      assert FamilyChatStore.quotes_for(room.id, [%{reply_to_message_id: 999_999_998}]) == %{}
    end

    # The reachable half of the same degradation: the target row genuinely
    # exists, so the foreign key is satisfied and the insert succeeds -- it
    # just is not in this room. A reader of this room must see an ordinary
    # message, never the other room's text.
    test "a target in another room renders as an ordinary message", %{room: room, sender: sender} do
      foreign_id = seed_archived_room_message!()

      {:ok, written} =
        FamilyChatStore.insert_message!(
          room.id,
          "user",
          sender,
          "Bunda",
          Ecto.UUID.generate(),
          "answers across a room boundary",
          foreign_id
        )

      {:ok, page} = FamilyChat.list_messages(sender, FamilyChat.canonical_room_slug(), limit: 50)
      rendered = Enum.find(page.nodes, &(&1.id == written.id))

      assert rendered.reply_to_message_id == foreign_id
      assert rendered.reply_to == nil
    end

    test "the application refuses to create a dangling reference at all", %{
      room: room,
      sender: sender
    } do
      assert_raise Exqlite.Error, ~r/FOREIGN KEY constraint failed/, fn ->
        FamilyChatStore.insert_message!(
          room.id,
          "user",
          sender,
          "Orphan Probe",
          Ecto.UUID.generate(),
          "answers a message that is not there",
          999_999_998
        )
      end
    end

    test "a quote resolves its sender name through the live-account seam", %{
      room: room,
      sender: sender
    } do
      {:ok, original} = commit(room, sender, "Nanti aku jemput jam 5")
      {:ok, reply} = reply_to(sender, original.id, "Oke, aku siapin")

      assert FamilyChat.live_sender_display_name(reply.reply_to, fn _sender_id -> "Renamed" end) ==
               "Renamed"

      assert FamilyChat.live_sender_display_name(reply.reply_to, fn _sender_id -> nil end) ==
               reply.reply_to.sender_display_name
    end

    test "a cross-room target is refused, and nothing commits", %{sender: sender} do
      foreign_id = seed_archived_room_message!()
      client_message_id = Ecto.UUID.generate()

      assert {:error, %{code: "VALIDATION_FAILED"}} =
               FamilyChat.send_message(
                 sender,
                 FamilyChat.canonical_room_slug(),
                 client_message_id,
                 "answer",
                 "Bunda",
                 foreign_id
               )

      assert FamilyChatStore.find_message(1, "user", sender, client_message_id) == nil
    end
  end

  # A second room only v1's data model allows, never its UI: seeded already
  # soft-deleted so `list_rooms_for/1` keeps reporting exactly one active room
  # (the behaviour corpus asserts that), while `message_by_id/2`'s room scoping
  # still has a genuinely foreign message to refuse.
  defp seed_archived_room_message! do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    BnestApp.SqliteRepo.query!(
      """
      INSERT OR IGNORE INTO family_chat_rooms (
        id, slug, name, room_kind, member_posting_enabled,
        created_at, created_by, updated_at, updated_by, deleted_at, deleted_by
      ) VALUES (900, 'ruang-arsip', 'Ruang Arsip', 'conversation', 1, ?, 'test', ?, 'test', ?, 'test')
      """,
      [now, now, now]
    )

    {:ok, foreign} =
      FamilyChatStore.insert_message!(
        900,
        "user",
        "test-user-family-chat-archive",
        "Arsip",
        "archive-" <> Ecto.UUID.generate(),
        "a message in another room"
      )

    foreign.id
  end

  defp commit(_room, sender, body) do
    FamilyChat.send_message(
      sender,
      FamilyChat.canonical_room_slug(),
      Ecto.UUID.generate(),
      body,
      "Ayah"
    )
  end

  defp reply_to(sender, target_id, body) do
    FamilyChat.send_message(
      sender,
      FamilyChat.canonical_room_slug(),
      Ecto.UUID.generate(),
      body,
      "Bunda",
      target_id
    )
  end
end
