defmodule BnestApp.SqliteRepo.Migrations.AddFamilyChat do
  @moduledoc false

  use Ecto.Migration

  def up do
    execute """
            CREATE TABLE family_chat_rooms (
              id INTEGER PRIMARY KEY,
              slug TEXT NOT NULL,
              name TEXT NOT NULL,
              room_kind TEXT NOT NULL CHECK (room_kind IN ('conversation')),
              member_posting_enabled INTEGER NOT NULL CHECK (member_posting_enabled IN (0, 1)),
              created_at TEXT NOT NULL,
              created_by TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              updated_by TEXT NOT NULL,
              deleted_at TEXT,
              deleted_by TEXT,
              CHECK (length(slug) BETWEEN 1 AND 64),
              CHECK (length(name) BETWEEN 1 AND 80),
              CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
            )
            """,
            "DROP TABLE family_chat_rooms"

    execute "CREATE UNIQUE INDEX family_chat_rooms_active_slug ON family_chat_rooms(slug) WHERE deleted_at IS NULL",
            "DROP INDEX family_chat_rooms_active_slug"

    execute """
            CREATE TABLE family_chat_messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              room_id INTEGER NOT NULL REFERENCES family_chat_rooms(id),
              sender_kind TEXT NOT NULL CHECK (sender_kind IN ('user', 'system')),
              sender_id TEXT NOT NULL,
              sender_display_name TEXT NOT NULL,
              idempotency_key TEXT NOT NULL,
              body TEXT NOT NULL,
              committed_at TEXT NOT NULL,
              created_by TEXT NOT NULL,
              UNIQUE(room_id, sender_kind, sender_id, idempotency_key),
              CHECK (length(sender_id) BETWEEN 1 AND 128),
              CHECK (length(sender_display_name) BETWEEN 1 AND 80),
              CHECK (length(idempotency_key) BETWEEN 1 AND 128),
              CHECK (length(CAST(body AS BLOB)) BETWEEN 1 AND 16384)
            )
            """,
            "DROP TABLE family_chat_messages"

    execute "CREATE INDEX family_chat_messages_room_id ON family_chat_messages(room_id, id DESC)",
            "DROP INDEX family_chat_messages_room_id"

    execute """
            CREATE TRIGGER family_chat_messages_no_update
            BEFORE UPDATE ON family_chat_messages
            BEGIN SELECT RAISE(ABORT, 'family chat messages are immutable'); END
            """,
            "DROP TRIGGER family_chat_messages_no_update"

    execute """
            CREATE TRIGGER family_chat_messages_no_delete
            BEFORE DELETE ON family_chat_messages
            BEGIN SELECT RAISE(ABORT, 'family chat messages are permanent'); END
            """,
            "DROP TRIGGER family_chat_messages_no_delete"

    execute """
            CREATE TABLE web_push_subscriptions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id TEXT NOT NULL,
              session_digest TEXT NOT NULL,
              endpoint_sha256 TEXT NOT NULL,
              endpoint TEXT NOT NULL,
              p256dh TEXT NOT NULL,
              auth_secret TEXT NOT NULL,
              expiration_time TEXT,
              created_at TEXT NOT NULL,
              created_by TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              updated_by TEXT NOT NULL,
              deleted_at TEXT,
              deleted_by TEXT,
              CHECK (length(session_digest) = 64),
              CHECK (length(endpoint_sha256) = 64),
              CHECK (length(endpoint) BETWEEN 1 AND 2048),
              CHECK (length(p256dh) BETWEEN 1 AND 256),
              CHECK (length(auth_secret) BETWEEN 1 AND 128),
              CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
            )
            """,
            "DROP TABLE web_push_subscriptions"

    execute "CREATE UNIQUE INDEX web_push_subscriptions_active_endpoint ON web_push_subscriptions(endpoint_sha256) WHERE deleted_at IS NULL",
            "DROP INDEX web_push_subscriptions_active_endpoint"

    execute "CREATE UNIQUE INDEX web_push_subscriptions_active_session ON web_push_subscriptions(user_id, session_digest) WHERE deleted_at IS NULL",
            "DROP INDEX web_push_subscriptions_active_session"

    execute """
            CREATE TABLE family_chat_push_deliveries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              message_id INTEGER NOT NULL REFERENCES family_chat_messages(id),
              subscription_id INTEGER NOT NULL REFERENCES web_push_subscriptions(id),
              state TEXT NOT NULL CHECK (state IN ('pending','claimed','retryable','delivered','terminal')),
              attempt_count INTEGER NOT NULL CHECK (attempt_count BETWEEN 0 AND 5),
              next_attempt_at TEXT,
              lease_expires_at TEXT,
              failure_category TEXT,
              provider_accepted_at TEXT,
              created_at TEXT NOT NULL,
              created_by TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              updated_by TEXT NOT NULL,
              deleted_at TEXT,
              deleted_by TEXT,
              UNIQUE(message_id, subscription_id),
              CHECK ((deleted_at IS NULL) = (deleted_by IS NULL)),
              CHECK (deleted_at IS NULL OR state IN ('delivered','terminal')),
              CHECK ((state = 'claimed') = (lease_expires_at IS NOT NULL)),
              CHECK (state IN ('pending','retryable') OR next_attempt_at IS NULL)
            )
            """,
            "DROP TABLE family_chat_push_deliveries"

    execute """
            CREATE INDEX family_chat_push_deliveries_due
              ON family_chat_push_deliveries(state, next_attempt_at, lease_expires_at, id)
              WHERE deleted_at IS NULL
            """,
            "DROP INDEX family_chat_push_deliveries_due"

    execute """
            CREATE INDEX family_chat_push_deliveries_retention
              ON family_chat_push_deliveries(updated_at, id)
              WHERE deleted_at IS NULL AND state IN ('delivered','terminal')
            """,
            "DROP INDEX family_chat_push_deliveries_retention"

    execute """
            CREATE INDEX family_chat_push_deliveries_purge
              ON family_chat_push_deliveries(deleted_at, id)
              WHERE deleted_at IS NOT NULL
            """,
            "DROP INDEX family_chat_push_deliveries_purge"
  end

  def down do
    %{rows: [[room_count]]} = repo().query!("SELECT COUNT(*) FROM family_chat_rooms")
    %{rows: [[message_count]]} = repo().query!("SELECT COUNT(*) FROM family_chat_messages")

    if room_count > 0 or message_count > 0 do
      raise "family chat migration refuses to reverse once feature rows exist"
    end

    execute "DROP INDEX family_chat_push_deliveries_purge"
    execute "DROP INDEX family_chat_push_deliveries_retention"
    execute "DROP INDEX family_chat_push_deliveries_due"
    execute "DROP TABLE family_chat_push_deliveries"
    execute "DROP INDEX web_push_subscriptions_active_session"
    execute "DROP INDEX web_push_subscriptions_active_endpoint"
    execute "DROP TABLE web_push_subscriptions"
    execute "DROP TRIGGER family_chat_messages_no_delete"
    execute "DROP TRIGGER family_chat_messages_no_update"
    execute "DROP INDEX family_chat_messages_room_id"
    execute "DROP TABLE family_chat_messages"
    execute "DROP INDEX family_chat_rooms_active_slug"
    execute "DROP TABLE family_chat_rooms"
  end
end
