defmodule BnestApp.TestInstance.AuditTest do
  # The end-of-run verdict (ADR 001, section 3): pure decisions over the facts the integration run gathers.
  # Every path is synthetic.
  use ExUnit.Case, async: true

  alias BnestApp.TestInstance.Audit

  @instance_dir "/synthetic/sqlite/test/runs/unit-run/instances/0123456789abcdef"
  @current %{instance_id: "fedcba9876543210", paths: %{}}
  @legacy_users "/synthetic/flat/test/runs/unit-run/users"

  test "a run that left nothing behind passes with no warning" do
    assert Audit.verdict([], nil, :ok) == {:ok, []}
  end

  test "an instance directory left behind fails the run and names it" do
    assert {:error, [reason]} = Audit.verdict([@instance_dir], nil, :ok)
    assert reason =~ @instance_dir
  end

  test "an instance that is still current fails the run and names its id" do
    assert {:error, [reason]} = Audit.verdict([], @current, :ok)
    assert reason =~ "fedcba9876543210"
  end

  test "base data outside the legacy roots fails the run and names each path" do
    base = {:error, ["/synthetic/flat/other/account.json", "/synthetic/sqlite/bnest.sqlite3"]}

    assert {:error, reasons} = Audit.verdict([], nil, base)
    assert length(reasons) == 2
    assert Enum.any?(reasons, &(&1 =~ "bnest.sqlite3"))
    assert Enum.any?(reasons, &(&1 =~ "account.json"))
  end

  test "base data under a legacy root is a warning, not a failure, and names the path" do
    base = {:error, ["#{@legacy_users}/user-test-bdd-0123"]}

    assert {:ok, [warning]} = Audit.verdict([], nil, base, [@legacy_users])
    assert warning =~ "user-test-bdd-0123"
  end

  test "a legacy root never excuses an instance leftover or a base file outside it" do
    base = {:error, ["#{@legacy_users}/user-test-bdd-0123", "/synthetic/sqlite/bnest.sqlite3"]}

    assert {:error, reasons} = Audit.verdict([@instance_dir], @current, base, [@legacy_users])
    assert length(reasons) == 3
    assert Enum.any?(reasons, &(&1 =~ "bnest.sqlite3"))
  end

  test "a legacy root matches a whole path segment, not a name prefix" do
    base = {:error, ["#{@legacy_users}-archive/user.json"]}

    assert {:error, [_reason]} = Audit.verdict([], nil, base, [@legacy_users])
  end

  test "a legacy root can name one shared database file and its sidecars, exactly" do
    db = "/synthetic/sqlite/test/runs/unit-run/bnest.sqlite3"
    legacy = [db, db <> "-wal", db <> "-shm"]

    assert {:ok, warnings} = Audit.verdict([], nil, {:error, [db, db <> "-wal"]}, legacy)
    assert length(warnings) == 2

    assert {:error, [reason]} = Audit.verdict([], nil, {:error, [db <> ".bak"]}, legacy)
    assert reason =~ "bnest.sqlite3.bak"
  end
end
