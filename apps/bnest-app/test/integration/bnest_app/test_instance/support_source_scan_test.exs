defmodule BnestApp.TestInstance.SupportSourceScanTest do
  # Test support must never build a database by itself: no DDL, no migrator, no copy of a
  # database file, no vacuum copy and no table-wide DELETE. Migrations reach a test instance only
  # through the production entry points. The scan reads text, so it lives in the integration layer.
  use ExUnit.Case, async: true

  @moduletag :test_instance

  # Scope: `test/support` only. The other compiled test roots hold pre-existing fixtures that
  # predate these rules, so they are not scanned here until those fixtures are decided.
  @support_root Path.expand("../../../support", __DIR__)

  # Every pattern ignores case, so `create table` and `CREATE TABLE` are both caught.
  @forbidden [
    {"DDL", ~r/\bCREATE\s+(TABLE|INDEX|TRIGGER|VIEW)\b/i},
    {"ALTER TABLE", ~r/\bALTER\s+TABLE\b/i},
    {"DROP TABLE", ~r/\bDROP\s+TABLE\b/i},
    {"VACUUM INTO", ~r/\bVACUUM\s+INTO\b/i},
    {"Ecto.Migrator", ~r/Ecto\.Migrator/i},
    {"priv/sqlite_repo", ~r/priv\/sqlite_repo/i},
    # Matches `File.cp`, `File.cp!`, `File.cp_r` and `File.copy`, and the Erlang `:file.copy`.
    {"file copy", ~r/\bfile\.(cp|copy)/i},
    {"table-wide DELETE", ~r/\bDELETE\s+FROM\s+\w+\s*["';]/i}
  ]

  # Each sample names the form it must be caught as. A form without a sample fails the test.
  @samples [
    {"DDL", "CREATE TABLE family_chat_rooms (id INTEGER)"},
    {"DDL", "create index bnest_records_owner on bnest_records (owner_id)"},
    {"ALTER TABLE", "ALTER TABLE bnest_schedules ADD COLUMN x TEXT"},
    {"ALTER TABLE", "alter table bnest_schedules rename to old_schedules"},
    {"DROP TABLE", "DROP TABLE bnest_schedules"},
    {"VACUUM INTO", "VACUUM INTO 'copy.sqlite3'"},
    {"Ecto.Migrator", "Ecto.Migrator.run(SqliteRepo, path, :up, all: true)"},
    {"priv/sqlite_repo", "Application.app_dir(:bnest_app, \"priv/sqlite_repo/migrations\")"},
    {"file copy", "File.cp!(source, destination)"},
    {"file copy", "File.cp_r(source, destination)"},
    {"file copy", "File.copy(source, destination)"},
    {"file copy", ":file.copy(source, destination)"},
    {"table-wide DELETE", "DELETE FROM bnest_schedules\""},
    {"table-wide DELETE", "delete from bnest_schedules;"}
  ]

  # Pre-existing fixture modules that predate the test-instance rules. Each entry names the one
  # rule it is exempt from. A stale entry fails the test, so this list only shrinks.
  @legacy_exemptions %{
    "restore_drill.ex" => ["DDL"]
  }

  test "every forbidden form is caught by its pattern, in any case" do
    for {name, _pattern} <- @forbidden do
      assert Enum.any?(@samples, &match?({^name, _sample}, &1)), "#{name} has no sample"
    end

    for {name, sample} <- @samples do
      assert pattern_matches?(pattern!(name), sample), "#{name} is not caught: #{sample}"
    end
  end

  test "a scoped delete is not a table-wide delete" do
    refute pattern_matches?(
             pattern!("table-wide DELETE"),
             "DELETE FROM bnest_schedule_runs WHERE x"
           )
  end

  test "no test support file holds a forbidden form outside its legacy exemption" do
    violations =
      for path <- support_files(),
          {name, pattern} <- @forbidden,
          pattern_matches?(pattern, File.read!(path)),
          not exempt?(path, name) do
        "#{Path.relative_to(path, @support_root)}: #{name}"
      end

    assert violations == []
  end

  test "every legacy exemption still names a file that holds the forbidden form" do
    for {file, names} <- @legacy_exemptions, name <- names do
      path = Path.join(@support_root, file)

      assert File.regular?(path), "#{file} is exempt but missing"
      assert pattern_matches?(pattern!(name), File.read!(path)), "#{file} no longer needs #{name}"
    end
  end

  defp pattern!(name) do
    {^name, pattern} = List.keyfind!(@forbidden, name, 0)
    pattern
  end

  defp support_files do
    Path.wildcard(Path.join(@support_root, "**/*.{ex,exs}"))
  end

  defp exempt?(path, name) do
    file = Path.basename(path)
    name in Map.get(@legacy_exemptions, file, [])
  end

  defp pattern_matches?(pattern, text), do: Regex.match?(pattern, text)
end
