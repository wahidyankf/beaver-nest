defmodule BnestApp.TestInstance.FingerprintTest do
  use ExUnit.Case, async: true

  alias BnestApp.TestInstance.Fingerprint

  @objects [
    [
      "table",
      "bnest_schedules",
      "bnest_schedules",
      "CREATE TABLE bnest_schedules (id INTEGER)"
    ],
    [
      "table",
      "schema_migrations",
      "schema_migrations",
      "CREATE TABLE schema_migrations (version INTEGER)"
    ]
  ]
  @versions [20_260_829_000_000, 20_260_830_000_000]
  @digest Fingerprint.digest(@objects, @versions)

  test "is a lowercase SHA-256 hex digest" do
    assert @digest =~ ~r/\A[0-9a-f]{64}\z/
  end

  test "does not depend on the order of the object rows or the versions" do
    assert Fingerprint.digest(Enum.reverse(@objects), Enum.reverse(@versions)) == @digest
  end

  test "changes when an object's SQL text changes" do
    [[type, name, table, _sql] | rest] = @objects
    changed = [[type, name, table, "CREATE TABLE bnest_schedules (id INTEGER, note TEXT)"] | rest]

    refute Fingerprint.digest(changed, @versions) == @digest
  end

  test "changes when an extra object exists" do
    extra = [
      "index",
      "test_extra_index",
      "bnest_schedules",
      "CREATE INDEX test_extra_index ON bnest_schedules (id)"
    ]

    refute Fingerprint.digest([extra | @objects], @versions) == @digest
  end

  test "changes when a migration version is missing or extra" do
    refute Fingerprint.digest(@objects, tl(@versions)) == @digest
    refute Fingerprint.digest(@objects, @versions ++ [20_260_922_000_000]) == @digest
  end

  test "keeps field boundaries, so moving text between fields changes the digest" do
    refute Fingerprint.digest([["table", "ab", "c", nil]], []) ==
             Fingerprint.digest([["table", "a", "bc", nil]], [])
  end
end
