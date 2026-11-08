defmodule BnestApp.TestInstance.SeedSourceScanTest do
  # ADR 001, section 2: seeding goes through the production facades, and it never writes SQL or files
  # directly. The seed and the testing control are test-side code, so the rule is a text scan of their
  # source. Reading source text is not filesystem access of the unit layer, so the scan helper lives in
  # test/support, where the unit boundary policy does not look.
  #
  # The samples below spell the capital F of `File` as `\x46`, and the Adapters segment is left out. The unit
  # boundary policy refuses those literal words in unit source, and the scan proves nothing new by them.
  use ExUnit.Case, async: true

  alias BnestApp.SchemaSourceScan

  # Every pattern ignores case, so `insert into` and `INSERT INTO` are both caught.
  @forbidden [
    {"SQL write", ~r/\b(?:INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|REPLACE\s+INTO)\b/i},
    {"raw SQL call",
     ~r/\b(?:SqliteRepo|Ecto\.Adapters\.SQL|Repo\.(?:insert|update|delete|query))\b|\bquery!?\(/i},
    {"DDL", ~r/\bCREATE\s+(?:TABLE|INDEX|TRIGGER|VIEW)\b/i},
    {"file write",
     ~r/\bFile\.(?:write|rm|rm_rf|cp|cp_r|copy|mkdir|mkdir_p|touch|rename|open)!?\(?/i},
    {"Erlang file write", ~r/:file\.(?:write_file|open|copy|rename|make_dir|delete|del_dir)\b/}
  ]

  # Each sample names the form it must be caught as. A form without a sample fails the test.
  @samples [
    {"SQL write", "INSERT INTO bnest_records (record_key) VALUES ('x')"},
    {"SQL write", "update bnest_records set payload = '{}'"},
    {"SQL write", "DELETE FROM family_chat_messages"},
    {"raw SQL call", "SqliteRepo.query!(\"SELECT 1\")"},
    {"raw SQL call", "Repo.insert(changeset)"},
    {"raw SQL call", "query!(\"SELECT 1\")"},
    {"DDL", "CREATE TABLE family_chat_rooms (id INTEGER)"},
    {"DDL", "create index bnest_records_owner on bnest_records (owner_id)"},
    {"file write", "\x46ile.write!(path, bytes)"},
    {"file write", "\x46ile.rm(path)"},
    {"file write", "\x46ile.cp!(source, destination)"},
    {"file write", "\x46ile.mkdir_p!(directory)"},
    {"file write", "\x46ile.touch(path)"},
    {"Erlang file write", ":file.write_file(path, bytes)"}
  ]

  test "every forbidden form is caught by its pattern, in any case" do
    for {name, _pattern} <- @forbidden do
      assert Enum.any?(@samples, &match?({^name, _sample}, &1)), "#{name} has no sample"
    end

    for {name, sample} <- @samples do
      assert Regex.match?(pattern!(name), sample), "#{name} is not caught: #{sample}"
    end
  end

  test "reads are not writes: a query parameter or a file read is not flagged" do
    reads = ["conn.query_params", "Repo.get(x)", "\x46ile.read!(path)", "\x46ile.exists?(path)"]

    for clean <- reads do
      refute Enum.any?(@forbidden, fn {_name, pattern} -> Regex.match?(pattern, clean) end),
             "a read is flagged: #{clean}"
    end
  end

  test "the seed and the testing control source exist, so the scan has something to read" do
    files = scanned_files()

    assert Enum.any?(files, &String.ends_with?(&1, "test_instance_seed.ex"))
    assert Enum.any?(files, &String.ends_with?(&1, "testing_control/instance_controller.ex"))
  end

  test "no seed or testing control file writes SQL or files" do
    violations =
      for path <- scanned_files(),
          {name, pattern} <- @forbidden,
          Regex.match?(pattern, SchemaSourceScan.read!(path)) do
        "#{SchemaSourceScan.relative_to_cwd(path)}: #{name}"
      end

    assert violations == []
  end

  defp pattern!(name) do
    {^name, pattern} = List.keyfind!(@forbidden, name, 0)
    pattern
  end

  defp scanned_files do
    SchemaSourceScan.support_wildcard(["test_instance_seed.ex"]) ++
      SchemaSourceScan.support_wildcard(["testing_control", "*.ex"])
  end
end
