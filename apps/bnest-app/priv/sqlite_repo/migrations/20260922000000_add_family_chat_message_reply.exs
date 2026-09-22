defmodule BnestApp.SqliteRepo.Migrations.AddFamilyChatMessageReply do
  @moduledoc false

  use Ecto.Migration

  def up do
    # `ADD COLUMN` with a `REFERENCES` clause is permitted only because the
    # column's default is NULL. It rewrites the table header rather than the
    # rows, so it stays constant-time however long the history is, and it is
    # DDL -- the `BEFORE UPDATE`/`BEFORE DELETE` triggers on this table do not
    # fire, so neither has to be suspended.
    execute "ALTER TABLE family_chat_messages ADD COLUMN reply_to_message_id INTEGER REFERENCES family_chat_messages(id)",
            "ALTER TABLE family_chat_messages DROP COLUMN reply_to_message_id"

    # Partial, because only replies carry the column and a full index would
    # cover every historical message for nothing.
    execute """
            CREATE INDEX family_chat_messages_reply_to
              ON family_chat_messages(reply_to_message_id)
              WHERE reply_to_message_id IS NOT NULL
            """,
            "DROP INDEX family_chat_messages_reply_to"
  end

  def down do
    %{rows: [[reply_count]]} =
      repo().query!("SELECT COUNT(*) FROM family_chat_messages WHERE reply_to_message_id IS NOT NULL")

    # Narrower than the family chat migration's own refusal, which guards any
    # room or message at all: only replies are lost by dropping this column,
    # and discarding links the family created to tidy a schema is not a
    # rollback. The release-level rollback is the real one -- a revision
    # without the column tolerates its presence.
    if reply_count > 0 do
      raise "family chat reply migration refuses to reverse once replies exist"
    end

    execute "DROP INDEX family_chat_messages_reply_to"
    execute "ALTER TABLE family_chat_messages DROP COLUMN reply_to_message_id"
  end
end
