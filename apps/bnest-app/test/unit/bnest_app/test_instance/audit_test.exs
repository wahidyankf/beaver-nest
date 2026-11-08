defmodule BnestApp.TestInstance.AuditTest do
  # The end-of-run verdict (ADR 001, section 3): pure decisions over the facts the integration run gathers.
  # Every path is synthetic.
  use ExUnit.Case, async: true

  alias BnestApp.TestInstance.Audit

  @instance_dir "/synthetic/sqlite/test/runs/unit-run/instances/0123456789abcdef"
  @current %{instance_id: "fedcba9876543210", paths: %{}}

  test "a run that left nothing behind passes" do
    assert Audit.verdict([], nil, :ok) == :ok
  end

  test "an instance directory left behind fails the run and names it" do
    assert {:error, [reason]} = Audit.verdict([@instance_dir], nil, :ok)
    assert reason =~ @instance_dir
  end

  test "an instance that is still current fails the run and names its id" do
    assert {:error, [reason]} = Audit.verdict([], @current, :ok)
    assert reason =~ "fedcba9876543210"
  end

  test "any base data fails the run and names each path" do
    base =
      {:error, ["/synthetic/flat/users/user-test-bdd-0123", "/synthetic/sqlite/bnest.sqlite3"]}

    assert {:error, reasons} = Audit.verdict([], nil, base)
    assert length(reasons) == 2
    assert Enum.any?(reasons, &(&1 =~ "user-test-bdd-0123"))
    assert Enum.any?(reasons, &(&1 =~ "bnest.sqlite3"))
  end

  test "base data is never excused, even under a flat users or accounts directory" do
    base = {:error, ["/synthetic/flat/system/accounts/account.json"]}

    assert {:error, [reason]} = Audit.verdict([], nil, base)
    assert reason =~ "account.json"
  end

  test "every leftover is reported together" do
    base = {:error, ["/synthetic/sqlite/bnest.sqlite3-wal"]}

    assert {:error, reasons} = Audit.verdict([@instance_dir], @current, base)
    assert length(reasons) == 3
    assert Enum.any?(reasons, &(&1 =~ "bnest.sqlite3-wal"))
  end

  # A synthetic run secret, the shape the runner generates (32 random bytes, hex encoded).
  @secret String.duplicate("a1", 32)

  test "a run-root file holding a run secret fails the run and names the file, never the secret" do
    files = [
      {"/synthetic/sqlite/test/runs/unit-run/bnest.sqlite3", "header " <> @secret <> " tail"},
      {"/synthetic/flat/test/runs/unit-run/clean.json", "{}"}
    ]

    assert [reason] = Audit.secret_leaks(files, [@secret])
    assert reason =~ "bnest.sqlite3"
    refute reason =~ @secret
  end

  test "a file without a run secret leaves no reason, and an empty secret matches nothing" do
    assert Audit.secret_leaks([{"/synthetic/a.json", "clean"}], [@secret]) == []
    assert Audit.secret_leaks([{"/synthetic/a.json", @secret}], []) == []
    assert Audit.secret_leaks([{"/synthetic/a.json", "anything"}], [""]) == []
  end

  test "a secret leak joins the other leftovers in the verdict" do
    leaks = Audit.secret_leaks([{"/synthetic/a.json", @secret}], [@secret])

    assert {:error, [reason]} = Audit.verdict([], nil, :ok, leaks)
    assert reason =~ "/synthetic/a.json"
  end
end
