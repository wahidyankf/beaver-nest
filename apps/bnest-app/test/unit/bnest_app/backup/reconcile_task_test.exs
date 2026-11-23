defmodule BnestApp.Backup.ReconcileTaskTest do
  # The usage refusal raises before the task reads configuration, a database
  # or a scheduler, so this test installs no adapter.
  use ExUnit.Case, async: true

  alias Mix.Tasks.Bnest.Backup.Reconcile

  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: The reconcile task refuses any argument with its usage line
  test "refuses any argument with its usage line before touching anything" do
    assert_raise Mix.Error, "usage: mix bnest.backup.reconcile", fn ->
      Reconcile.run(["--unexpected"])
    end
  end
end
