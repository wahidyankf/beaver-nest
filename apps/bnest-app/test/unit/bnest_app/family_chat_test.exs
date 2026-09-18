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
end
