defmodule BnestApp.Storage.PointerIsolationTest do
  use ExUnit.Case, async: true

  # The real storage pointer names the production database, so the unit layer must resolve
  # its own absent pointer and a run-scoped default directory.
  test "the unit layer resolves a run-scoped storage pointer and profile, never the real ones" do
    pointer = Application.fetch_env!(:bnest_app, :storage_config_path)
    {:test, run_id} = Application.fetch_env!(:bnest_app, :storage_profile)

    assert is_binary(run_id) and run_id != ""
    assert pointer =~ "/bnest/data/test/runs/#{run_id}/storage-config/"
    refute pointer =~ "/.config/bnest/"
  end
end
