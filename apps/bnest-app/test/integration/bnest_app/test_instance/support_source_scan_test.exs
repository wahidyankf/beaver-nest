defmodule BnestApp.TestInstance.SupportSourceScanTest do
  # Test support must never build a database by itself: no DDL, no migrator, no copy of a
  # database file and no table-wide DELETE. Migrations reach a test instance only through the
  # production entry points. The scan reads text, so it lives in the integration layer.
  use ExUnit.Case, async: true

  @moduletag :test_instance

  @support_root Path.expand("../../../support", __DIR__)

  @forbidden [
    {"DDL", ~r/\bCREATE\s+(TABLE|INDEX|TRIGGER|VIEW)\b/},
    {"ALTER TABLE", ~r/\bALTER\s+TABLE\b/},
    {"Ecto.Migrator", ~r/Ecto\.Migrator/},
    {"priv/sqlite_repo", ~r/priv\/sqlite_repo/},
    {"file copy", ~r/\bFile\.cp!?\(?/},
    {"table-wide DELETE", ~r/DELETE\s+FROM\s+\w+\s*["';]/}
  ]

  # Pre-existing fixture modules that predate the test-instance rules. Each entry names the one
  # rule it is exempt from. A stale entry fails the test, so this list only shrinks.
  @legacy_exemptions %{
    "restore_drill.ex" => ["DDL"]
  }

  test "every forbidden form is caught by its pattern" do
    samples = %{
      "DDL" => "CREATE TABLE family_chat_rooms (id INTEGER)",
      "ALTER TABLE" => "ALTER TABLE bnest_schedules ADD COLUMN x TEXT",
      "Ecto.Migrator" => "Ecto.Migrator.run(SqliteRepo, path, :up, all: true)",
      "priv/sqlite_repo" => "Application.app_dir(:bnest_app, \"priv/sqlite_repo/migrations\")",
      "file copy" => "File.cp!(source, destination)",
      "table-wide DELETE" => "DELETE FROM bnest_schedules\""
    }

    for {name, pattern} <- @forbidden do
      assert pattern_matches?(pattern, Map.fetch!(samples, name)), "#{name} is not caught"
    end
  end

  test "a scoped delete is not a table-wide delete" do
    {_name, pattern} = List.keyfind!(@forbidden, "table-wide DELETE", 0)

    refute pattern_matches?(pattern, "DELETE FROM bnest_schedule_runs WHERE run_id IN (")
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
      {_name, pattern} = List.keyfind!(@forbidden, name, 0)

      assert File.regular?(path), "#{file} is exempt but missing"
      assert pattern_matches?(pattern, File.read!(path)), "#{file} no longer needs #{name}"
    end
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
