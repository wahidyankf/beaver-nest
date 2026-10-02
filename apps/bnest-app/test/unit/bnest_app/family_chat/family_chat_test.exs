defmodule BnestApp.FamilyChatTest do
  # `async: false`: the facade serves the one in-memory room store this test installs
  # under a registered name (the unit layer's configured `:room_store`), so no other
  # test may install its own meanwhile.
  use ExUnit.Case, async: false

  alias BnestApp.FamilyChat
  alias BnestApp.FamilyChat.Ports.RoomStore
  alias BnestApp.Scheduler
  alias BnestApp.Test.InMemory.MessagePublisher
  alias BnestApp.Test.InMemory.RoomStore, as: InMemoryRoomStore
  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore
  alias BnestApp.Test.InMemory.SubscriptionStore, as: InMemorySubscriptionStore

  setup do
    store = InMemoryRoomStore.install()
    :ok = MessagePublisher.forget_published()
    {:ok, store: store}
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

    test "list_rooms_for/1 rejects a nil user id" do
      assert {:error, %{code: "UNAUTHENTICATED", details: nil}} = FamilyChat.list_rooms_for(nil)
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
  end

  describe "the configured room store" do
    test "a test that installed none is told so instead of being served one" do
      stop_supervised!(InMemoryRoomStore)

      assert_raise ArgumentError, ~r/no in-memory room store is installed/, fn ->
        FamilyChat.canonical_room()
      end
    end

    test "ensure_ready!/0 and migrate!/0 seed the canonical room once", %{store: store} do
      assert FamilyChat.ensure_ready!() == :ok
      assert {:ok, room} = FamilyChat.migrate!()
      assert {:ok, ^room} = FamilyChat.migrate!()

      assert %{id: 1, slug: "ruang-keluarga", name: "Ruang Keluarga", room_kind: "conversation"} =
               room

      assert FamilyChat.canonical_room() == room
      assert RoomStore.list_active_rooms(store) == [room]
      assert FamilyChat.list_rooms_for("test-user-family-chat-rooms") == {:ok, [room]}
    end

    # The start-time convergence is the facade's own, on whatever room store is configured:
    # the seeded retention schedule becomes enabled and the backup schedule moves to 18:00
    # UTC, each once, read back through the Scheduler.
    test "converge_after_drain!/0 enables push retention and converges the backup time once" do
      schedules = InMemoryScheduleStore.install()
      now = ~U[2026-09-18 00:00:00Z]
      backup_key = "prod-sqlite-backup-daily"
      retention_key = "family-chat-push-retention-daily"

      :ok =
        InMemoryScheduleStore.put_daily_schedule(
          schedules,
          backup_key,
          "prod_sqlite_backup",
          "admin_system",
          now
        )

      :ok =
        InMemoryScheduleStore.put_daily_schedule(
          schedules,
          retention_key,
          "family_chat_push_retention",
          "admin_system",
          now,
          %{daily_at_utc: "17:15", enabled: false}
        )

      assert FamilyChat.converge_after_drain!() == :ok
      assert %{daily_at_utc: "18:00"} = backup = Scheduler.get_schedule(backup_key)

      assert %{enabled: true, daily_at_utc: "17:15"} =
               retention = Scheduler.get_schedule(retention_key)

      assert FamilyChat.converge_after_drain!() == :ok
      assert Scheduler.get_schedule(backup_key) == backup
      assert Scheduler.get_schedule(retention_key) == retention
    end

    test "insert_message!/6 commits a trusted producer's message as given, unpublished", %{
      store: store
    } do
      subscription = InMemorySubscriptionStore.subscribe!(store, "test-user-family-chat-device")
      room = FamilyChat.canonical_room()

      assert {:ok, message} =
               FamilyChat.insert_message!(
                 room.id,
                 "system",
                 "test-user-family-chat-producer",
                 "System",
                 "producer-key",
                 "  kept exactly as given  "
               )

      assert message.body == "  kept exactly as given  "
      assert message.reply_to_message_id == nil
      assert message.deliveries == [%{subscription_id: subscription, state: "pending"}]
      refute_received {:family_chat_published, _topic, _message}
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

    test "reports an archived room as not found", %{store: store} do
      archive_room!(store)

      assert {:error, %{code: "ROOM_NOT_FOUND", details: nil}} =
               FamilyChat.get_room_for("test-user-family-chat-message-shape", "ruang-arsip")
    end
  end

  describe "list_messages/3" do
    test "refuses both cursors at once and a limit outside 1 to 50" do
      user = "test-user-family-chat-pages"
      slug = FamilyChat.canonical_room_slug()

      for options <- [[before_id: 5, after_id: 1], [limit: 0], [limit: 51], [limit: "10"]] do
        assert {:error, %{code: "VALIDATION_FAILED", details: nil}} =
                 FamilyChat.list_messages(user, slug, options)
      end
    end

    test "pages the room's messages ascending, each tagged with its room" do
      user = "test-user-family-chat-pages"
      slug = FamilyChat.canonical_room_slug()
      ids = for n <- 1..3, do: elem(commit(user, "page #{n}"), 1).id

      assert {:ok, %{nodes: nodes, has_older: false, has_newer: false}} =
               FamilyChat.list_messages(user, slug, [])

      assert Enum.map(nodes, & &1.id) == ids
      assert Enum.all?(nodes, &(&1.room_slug == slug and &1.reply_to == nil))

      assert {:ok, %{nodes: [last], has_older: true}} =
               FamilyChat.list_messages(user, slug, limit: 1)

      assert last.id == List.last(ids)
    end

    test "reports a missing room after the cursor is accepted" do
      assert {:error, %{code: "ROOM_NOT_FOUND", details: nil}} =
               FamilyChat.list_messages("test-user-family-chat-pages", "no-such-room", [])
    end
  end

  describe "send_message/4" do
    test "commits, publishes once on the room's topic, and replays without a second publish" do
      user = "test-user-family-chat-sender"
      client_message_id = Ecto.UUID.generate()
      slug = FamilyChat.canonical_room_slug()

      assert {:ok, message} =
               FamilyChat.send_message(user, slug, client_message_id, " Dinner is ready ")

      assert %{
               body: "Dinner is ready",
               sender_kind: "user",
               sender_id: ^user,
               sender_display_name: ^user,
               room_slug: ^slug,
               broadcast_scope: :local,
               reply_to: nil
             } = message

      topic = FamilyChat.subscription_topic(message.room_id)
      assert topic == "family_chat_room:1"
      assert_received {:family_chat_published, ^topic, ^message}

      assert {:ok, replayed} =
               FamilyChat.send_message(user, slug, client_message_id, "a different body", "Ayah")

      assert replayed.id == message.id
      assert replayed.body == "Dinner is ready"
      refute_received {:family_chat_published, _topic, _message}
    end

    test "refuses an invalid client message ID and an invalid body before committing" do
      user = "test-user-family-chat-sender"
      slug = FamilyChat.canonical_room_slug()

      assert {:error, %{code: "VALIDATION_FAILED"}} =
               FamilyChat.send_message(user, slug, "not-a-uuid", "hi")

      assert {:error, %{code: "VALIDATION_FAILED"}} =
               FamilyChat.send_message(user, slug, Ecto.UUID.generate(), "   ")

      assert {:ok, %{nodes: []}} = FamilyChat.list_messages(user, slug, [])
      refute_received {:family_chat_published, _topic, _message}
    end

    test "rejects posting while the room has member posting disabled", %{store: store} do
      user = "test-user-family-chat-posting-disabled-" <> Ecto.UUID.generate()
      slug = FamilyChat.canonical_room_slug()
      room = FamilyChat.canonical_room()
      :ok = InMemoryRoomStore.put_room(store, %{room | member_posting_enabled: false})

      assert {:error, %{code: "FORBIDDEN", details: nil}} =
               FamilyChat.send_message(user, slug, Ecto.UUID.generate(), "should be forbidden")
    end
  end

  describe "post_system_message/3" do
    test "reports a nonexistent room as not found (resolve_room/2's own lookup)" do
      assert {:error, %{code: "ROOM_NOT_FOUND", details: nil}} =
               FamilyChat.post_system_message(
                 "no-such-room-ever-seeded",
                 "system:test-fixture",
                 "notice"
               )
    end

    test "commits once per producer key as the system sender, and refuses a blank body" do
      slug = FamilyChat.canonical_room_slug()

      assert {:ok, posted} =
               FamilyChat.post_system_message(slug, "system:test-producer", "notice")

      assert %{sender_kind: "system", sender_id: "system:test-producer"} = posted
      assert posted.sender_display_name == "System"
      assert posted.idempotency_key == "system:test-producer"

      assert {:ok, retried} =
               FamilyChat.post_system_message(slug, "system:test-producer", "other notice")

      assert retried.id == posted.id

      assert {:error, %{code: "VALIDATION_FAILED"}} =
               FamilyChat.post_system_message(slug, "system:test-producer-2", " ")
    end
  end

  describe "replying" do
    setup do
      {:ok, sender: "test-user-family-chat-reply-" <> Ecto.UUID.generate()}
    end

    test "a commit carries its reply target and resolves the quote", %{sender: sender} do
      {:ok, original} = commit(sender, "Nanti aku jemput jam 5")
      {:ok, reply} = reply_to(sender, original.id, "Oke, aku siapin")

      assert reply.reply_to_message_id == original.id
      assert reply.reply_to.id == original.id
      assert reply.reply_to.body_preview == "Nanti aku jemput jam 5"
      assert reply.reply_to.sender_kind == "user"
    end

    test "a message sent with no target has no quote", %{sender: sender} do
      {:ok, message} = commit(sender, "Dinner is ready")

      assert message.reply_to_message_id == nil
      assert message.reply_to == nil
    end

    test "the preview collapses whitespace and cuts at 160 graphemes", %{sender: sender} do
      long = String.duplicate("a", 400)
      {:ok, original} = commit(sender, long)
      {:ok, reply} = reply_to(sender, original.id, "answer")

      assert String.length(reply.reply_to.body_preview) == 161
      assert String.ends_with?(reply.reply_to.body_preview, "…")
    end

    test "a short body is previewed whole, with no ellipsis", %{sender: sender} do
      {:ok, original} = commit(sender, "short enough")
      {:ok, reply} = reply_to(sender, original.id, "answer")

      assert reply.reply_to.body_preview == "short enough"
      refute String.ends_with?(reply.reply_to.body_preview, "…")
    end

    test "newlines and runs of whitespace collapse to single spaces", %{sender: sender} do
      {:ok, original} = commit(sender, "first line\n\n  second     line")
      {:ok, reply} = reply_to(sender, original.id, "answer")

      assert reply.reply_to.body_preview == "first line second line"
    end

    test "a target no message has is refused, and nothing commits", %{
      store: store,
      sender: sender
    } do
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

      assert RoomStore.find_message(store, 1, "user", sender, client_message_id) == nil
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
      sender: sender
    } do
      {:ok, first_target} = commit(sender, "first target")
      {:ok, second_target} = commit(sender, "second target")

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

    test "a page resolves every quote its replies name", %{sender: sender} do
      {:ok, a} = commit(sender, "target a")
      {:ok, b} = commit(sender, "target b")
      {:ok, _reply_a} = reply_to(sender, a.id, "answers a")
      {:ok, _reply_b} = reply_to(sender, b.id, "answers b")

      {:ok, page} = FamilyChat.list_messages(sender, FamilyChat.canonical_room_slug(), [])
      quoted = for %{reply_to: %{id: id, body_preview: preview}} <- page.nodes, do: {id, preview}

      assert quoted == [{a.id, "target a"}, {b.id, "target b"}]
    end

    # The degradation a reader can still meet: the target genuinely exists, so the
    # store accepts the reference -- it just is not in this room. A reader of this
    # room must see an ordinary message, never the other room's text. Only a
    # trusted write through the room store itself can produce such a row.
    test "a target in another room renders as an ordinary message", %{
      store: store,
      sender: sender
    } do
      foreign_id = archive_room!(store)

      {:ok, written} =
        RoomStore.insert_message!(
          store,
          1,
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

    test "a quote resolves its sender name through the live-account seam", %{sender: sender} do
      {:ok, original} = commit(sender, "Nanti aku jemput jam 5")
      {:ok, reply} = reply_to(sender, original.id, "Oke, aku siapin")

      assert FamilyChat.live_sender_display_name(reply.reply_to, fn _sender_id -> "Renamed" end) ==
               "Renamed"

      assert FamilyChat.live_sender_display_name(reply.reply_to, fn _sender_id -> nil end) ==
               reply.reply_to.sender_display_name
    end

    test "a cross-room target is refused, and nothing commits", %{store: store, sender: sender} do
      foreign_id = archive_room!(store)
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

      assert RoomStore.find_message(store, 1, "user", sender, client_message_id) == nil
    end
  end

  # A second room only v1's data model allows, never its UI: archived from the start
  # so `list_rooms_for/1` keeps reporting exactly one active room, while
  # `message_by_id/3`'s room scoping still has a genuinely foreign message to refuse.
  defp archive_room!(store) do
    archived = %{FamilyChat.canonical_room() | id: 900, slug: "ruang-arsip", name: "Ruang Arsip"}
    :ok = InMemoryRoomStore.put_room(store, archived, deleted?: true)

    {:ok, foreign} =
      FamilyChat.insert_message!(
        900,
        "user",
        "test-user-family-chat-archive",
        "Arsip",
        "archive-" <> Ecto.UUID.generate(),
        "a message in another room"
      )

    foreign.id
  end

  defp commit(sender, body) do
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
