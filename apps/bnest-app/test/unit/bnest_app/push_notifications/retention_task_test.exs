defmodule BnestApp.PushNotifications.RetentionTaskTest do
  # Not async: the Scheduler and the Push Notifications facade serve the one in-memory
  # schedule store and room store this test installs under registered names.
  use ExUnit.Case, async: false

  alias BnestApp.Scheduler
  alias BnestApp.Test.InMemory.RoomStore, as: InMemoryRoomStore
  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore

  @now ~U[2026-09-18 20:00:00Z]

  # The push retention schedule as Family Chat's release seeds it, enabled and due at its
  # 17:15 UTC slot.
  setup do
    _room_store = InMemoryRoomStore.install()
    store = InMemoryScheduleStore.install()

    :ok =
      InMemoryScheduleStore.put_daily_schedule(
        store,
        "family-chat-push-retention-daily",
        "family_chat_push_retention",
        "admin_system",
        @now,
        %{daily_at_utc: "17:15"}
      )

    {:ok, store: store}
  end

  test "a scheduled retention run records itself verified and is not run again once its lease ends",
       %{store: store} do
    assert [%{attempt: 1} = claim] = Scheduler.claim_due(@now)
    assert :ok = Scheduler.execute(claim, @now)

    assert [%{state: "verified", attempt: 1, artifact_basename: nil, failure_category: nil} = run] =
             InMemoryScheduleStore.runs(store)

    assert run.run_id == claim.run_id

    # Past the attempt's 15-minute lease, a run left running would be claimed again.
    assert Scheduler.claim_due(DateTime.add(@now, 16 * 60)) == []
    assert [%{state: "verified"}] = InMemoryScheduleStore.runs(store)
  end
end
