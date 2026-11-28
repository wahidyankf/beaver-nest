defmodule BnestApp.Test.SchemaGolden do
  @moduledoc """
  The committed golden dump of a migrated database's schema: each table with its columns in order, each index with
  its columns, and the applied migration versions. A spawned test instance and a database built by the release
  migration entry points must both equal the committed dump, so a migration that adds, drops or changes a table, a
  column or an index fails the integration layer even when both databases change in the same way.

  The dump holds the schema and the versions only, never rows or values. The file is
  `test/fixtures/test_instance_schema_golden.json`. Write it again only after a deliberate schema change, with the
  test that reads it:

      BNEST_WRITE_SCHEMA_GOLDEN=1 BNEST_TEST_LAYER=integration MIX_ENV=test mix test test/integration/bnest_app/storage/test_instance_schema_test.exs
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.SqliteRepo

  @fixture Path.expand("../../fixtures/test_instance_schema_golden.json", __DIR__)

  @doc "The normalized schema of the current database: its tables, its indexes, and the applied versions."
  def current do
    tables = Enum.map(table_names(), &table/1)

    %{
      "tables" => tables,
      "indexes" => tables |> Enum.flat_map(&table_indexes(&1["name"])) |> Enum.sort(),
      "versions" => applied_versions()
    }
  end

  @doc "The dump committed in the fixture file, decoded."
  def committed, do: @fixture |> File.read!() |> Jason.decode!()

  @doc "Writes the dump to the fixture file. Called only when the schema changes on purpose."
  def write!(dump) do
    File.write!(@fixture, [Jason.encode_to_iodata!(dump, pretty: true), "\n"])
  end

  defp applied_versions do
    %{rows: rows} = SqliteRepo.query!("SELECT version FROM schema_migrations ORDER BY version")
    Enum.map(rows, fn [version] -> version end)
  end

  defp table_names do
    %{rows: rows} =
      SqliteRepo.query!(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
      )

    Enum.map(rows, fn [name] -> name end)
  end

  defp table(name) do
    %{rows: rows} = SqliteRepo.query!(~s[PRAGMA table_info("#{name}")])

    columns =
      Enum.map(rows, fn [_cid, column, type, notnull, _default, pk] ->
        [column, type, notnull, pk]
      end)

    %{"name" => name, "columns" => columns}
  end

  defp table_indexes(table) do
    %{rows: rows} = SqliteRepo.query!(~s[PRAGMA index_list("#{table}")])

    Enum.map(rows, fn [_seq, name, unique, origin, _partial] ->
      %{
        "table" => table,
        "name" => name,
        "unique" => unique,
        "origin" => origin,
        "columns" => index_columns(name)
      }
    end)
  end

  defp index_columns(name) do
    %{rows: rows} = SqliteRepo.query!(~s[PRAGMA index_info("#{name}")])
    Enum.map(rows, fn [_seqno, _cid, column] -> column end)
  end
end
