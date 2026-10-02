defmodule BnestApp.Scheduler.InMemoryScheduleStoreTest do
  use BnestApp.Test.Contracts.ScheduleStoreContract, async: true

  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore

  defp new_store(_context), do: InMemoryScheduleStore.start()

  defp put_schedule(store, schedule),
    do: :ok = InMemoryScheduleStore.put_schedule(store, schedule)

  test "reads back every run with the columns a stored run carries", %{store: store} do
    put_schedule(store, schedule())
    [claim] = ScheduleStore.claim_due(store, at())

    receipt = %{
      "artifactBasename" => "bnest-in-memory.sqlite3",
      "artifactSha256" => String.duplicate("b", 64),
      "artifactBytes" => 7
    }

    :ok = ScheduleStore.complete(store, claim.run_id, 1, receipt, at(60))

    assert InMemoryScheduleStore.runs(store) == [
             %{
               claim
               | state: "verified",
                 lease_expires_at: nil,
                 artifact_basename: "bnest-in-memory.sqlite3",
                 artifact_sha256: String.duplicate("b", 64),
                 artifact_bytes: 7,
                 finished_at: at(60)
             }
           ]
  end

  test "the installed store serves new/0 until the test exits" do
    installed = InMemoryScheduleStore.install()

    assert InMemoryScheduleStore.new() == installed
    put_schedule(installed, schedule())
    assert ScheduleStore.get_schedule(InMemoryScheduleStore.new(), "contract-daily") == schedule()
  end
end
