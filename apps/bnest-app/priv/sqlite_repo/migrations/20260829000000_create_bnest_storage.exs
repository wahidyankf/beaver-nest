defmodule BnestApp.SqliteRepo.Migrations.CreateBnestStorage do
  @moduledoc false

  use Ecto.Migration

  def up do
    execute """
            CREATE TABLE bnest_records (
              record_type TEXT NOT NULL,
              record_key TEXT NOT NULL,
              owner_id TEXT NULL,
              schema_version INTEGER NOT NULL CHECK (schema_version > 0),
              revision INTEGER NULL CHECK (revision IS NULL OR revision >= 0),
              payload_json TEXT NOT NULL CHECK (json_valid(payload_json)),
              payload_sha256 TEXT NOT NULL CHECK (length(payload_sha256) = 64),
              inserted_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              PRIMARY KEY (record_type, record_key)
            )
            """,
            "DROP TABLE bnest_records"

    execute "CREATE INDEX bnest_records_owner_type ON bnest_records (owner_id, record_type)",
            "DROP INDEX bnest_records_owner_type"

    execute """
            CREATE TABLE bnest_recovery_sources (
              owner_kind TEXT NOT NULL CHECK (owner_kind IN ('app','user')),
              owner_key TEXT NOT NULL,
              import_id TEXT NOT NULL,
              payload_blob BLOB NOT NULL,
              payload_sha256 TEXT NOT NULL CHECK (length(payload_sha256) = 64),
              byte_size INTEGER NOT NULL CHECK (byte_size >= 0),
              inserted_at TEXT NOT NULL,
              PRIMARY KEY (owner_kind, owner_key, import_id)
            )
            """,
            "DROP TABLE bnest_recovery_sources"

    execute """
            CREATE TABLE bnest_migration_runs (
              migration_id TEXT PRIMARY KEY,
              source_fingerprint TEXT NOT NULL,
              ddl_checksum TEXT NOT NULL,
              state TEXT NOT NULL CHECK (state IN
                ('inventoried','copying','verifying','verified','failed')),
              started_at TEXT NOT NULL,
              verified_at TEXT NULL,
              error_category TEXT NULL
            )
            """,
            "DROP TABLE bnest_migration_runs"

    execute """
            CREATE TABLE bnest_migration_items (
              migration_id TEXT NOT NULL REFERENCES bnest_migration_runs(migration_id),
              source_relative_path TEXT NOT NULL,
              record_type TEXT NOT NULL,
              record_key TEXT NOT NULL,
              source_sha256 TEXT NOT NULL,
              target_sha256 TEXT NULL,
              outcome TEXT NOT NULL CHECK (outcome IN
                ('pending','accepted','unsupported','invalid','changed','failed')),
              error_category TEXT NULL,
              PRIMARY KEY (migration_id, source_relative_path),
              UNIQUE (migration_id, record_type, record_key)
            )
            """,
            "DROP TABLE bnest_migration_items"

    execute "CREATE INDEX bnest_migration_items_outcome ON bnest_migration_items (migration_id, outcome)",
            "DROP INDEX bnest_migration_items_outcome"
  end

  def down do
    records_count = repo().aggregate("bnest_records", :count)
    runs_count = repo().aggregate("bnest_migration_runs", :count)

    if records_count > 0 or runs_count > 0 do
      raise "bnest storage migration refuses to reverse once records or migration evidence exist"
    end

    execute "DROP INDEX bnest_migration_items_outcome"
    execute "DROP TABLE bnest_migration_items"
    execute "DROP TABLE bnest_migration_runs"
    execute "DROP TABLE bnest_recovery_sources"
    execute "DROP INDEX bnest_records_owner_type"
    execute "DROP TABLE bnest_records"
  end
end
