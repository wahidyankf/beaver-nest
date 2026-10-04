defmodule BnestApp.Test.Contracts.ScheduleStoreContract do
  @moduledoc """
  The behaviour every `BnestApp.Scheduler.Ports.ScheduleStore` implementation shares: due
  claims and the inputs their slots are computed from, setup claims, leases, retries and
  results, the inventory, the verified runs a handler's ledger reports, and the daily and
  pristine edits. A test module uses this
  template and defines:

    * `new_store/1`, which takes the ExUnit context and returns a handle over a fresh store
      with no schedule and no run;
    * `put_schedule/2`, which takes the handle and a full schedule (see `schedule/1`) and
      stores it as is, replacing a stored schedule with the same key, the way that store's
      schedules come to exist from release seeds.

  Every other change goes through the port, at fixed instants. The schedule contexts and
  claim keys are those the database accepts.
  """

  use ExUnit.CaseTemplate

  alias BnestApp.Scheduler.Ports.ScheduleStore

  # 20:00 UTC: a 19:00 daily schedule's latest slot is today's, its next tomorrow's.
  @now ~U[2026-09-18 20:00:00Z]
  @slot ~U[2026-09-18 19:00:00Z]
  @next_slot ~U[2026-09-19 19:00:00Z]

  @doc "The contract's clock, `seconds` later."
  @spec at(integer()) :: DateTime.t()
  def at(seconds \\ 0), do: DateTime.add(@now, seconds, :second)

  @doc "The latest 19:00 slot at the contract's clock."
  @spec slot() :: DateTime.t()
  def slot, do: @slot

  @doc "The next 19:00 slot at the contract's clock."
  @spec next_slot() :: DateTime.t()
  def next_slot, do: @next_slot

  @doc """
  A pristine, enabled, never-expiring daily family schedule at 19:00 UTC, due at its latest
  slot, with the given fields replaced.
  """
  @spec schedule(map()) :: ScheduleStore.schedule()
  def schedule(fields \\ %{}) do
    Map.merge(
      %{
        schedule_key: "contract-daily",
        handler_key: "fixture",
        schedule_context: "family",
        cadence: "daily",
        daily_at_utc: "19:00",
        enabled: true,
        expiration_kind: "never",
        expires_at: nil,
        max_occurrences: nil,
        claimed_occurrences: 0,
        expired_at: nil,
        next_run_at: @slot,
        revision: 1,
        inserted_at: at(-86_400),
        updated_at: at(-86_400)
      },
      fields
    )
  end

  @doc """
  The receipt of a verified run's artifact `name`, as the backup task records it, and the
  verified-run view `verified_runs/2` reports it as.
  """
  @spec receipt(String.t()) :: map()
  def receipt(name) do
    %{
      "artifactBasename" => "bnest-contract-#{name}.sqlite3",
      "artifactSha256" => :sha256 |> :crypto.hash(name) |> Base.encode16(case: :lower),
      "artifactBytes" => byte_size(name) * 1_000
    }
  end

  @spec verified_view(String.t(), DateTime.t() | nil, DateTime.t(), String.t()) :: map()
  def verified_view(run_id, slot, finished_at, name) do
    receipt = receipt(name)

    %{
      run_id: run_id,
      slot: slot,
      finished_at: finished_at,
      artifact_basename: receipt["artifactBasename"],
      artifact_sha256: receipt["artifactSha256"],
      artifact_bytes: receipt["artifactBytes"]
    }
  end

  @doc "The keys of the claimed runs, in claim order."
  @spec keys([ScheduleStore.run()]) :: [String.t()]
  def keys(runs), do: Enum.map(runs, & &1.schedule_key)

  @doc "The inventory row of the schedule with the key."
  @spec row(ScheduleStore.handle(), String.t()) :: map()
  def row(store, key), do: Enum.find(ScheduleStore.inventory(store), &(&1.schedule_key == key))

  using do
    quote do
      import BnestApp.Test.Contracts.ScheduleStoreContract, only: :functions

      alias BnestApp.Scheduler.Ports.ScheduleStore
      alias BnestApp.Test.Contracts.ScheduleStoreContract

      require ScheduleStoreContract

      setup context, do: [store: new_store(context)]

      describe "ScheduleStore claim contract" do
        test "claims the latest due slot once and moves the next run to the next slot",
             %{store: store} do
          put_schedule(store, schedule(%{next_run_at: DateTime.add(slot(), -2 * 86_400)}))

          assert [%{run_id: run_id} = run] = ScheduleStore.claim_due(store, at())
          assert is_binary(run_id)

          assert Map.delete(run, :run_id) == %{
                   schedule_key: "contract-daily",
                   claim_key: "slot:2026-09-18T19:00:00Z",
                   claim_kind: "scheduled",
                   scheduled_for: slot(),
                   schedule_revision: 1,
                   occurrence_number: 1,
                   attempt: 1,
                   state: "running",
                   lease_expires_at: at(15 * 60),
                   next_attempt_at: nil,
                   artifact_basename: nil,
                   artifact_sha256: nil,
                   artifact_bytes: nil,
                   failure_category: nil,
                   started_at: at(),
                   finished_at: nil
                 }

          assert ScheduleStore.get_schedule(store, "contract-daily") ==
                   schedule(%{next_run_at: next_slot(), claimed_occurrences: 1, updated_at: at()})

          assert ScheduleStore.claim_due(store, at()) == []
        end

        test "claims only enabled, unexpired, due schedules, in next-run then key order",
             %{store: store} do
          put_schedule(store, schedule(%{schedule_key: "b-due"}))
          put_schedule(store, schedule(%{schedule_key: "a-due"}))

          put_schedule(
            store,
            schedule(%{schedule_key: "c-earlier", next_run_at: DateTime.add(slot(), -86_400)})
          )

          put_schedule(store, schedule(%{schedule_key: "disabled", enabled: false}))
          put_schedule(store, schedule(%{schedule_key: "expired", expired_at: at(-60)}))
          put_schedule(store, schedule(%{schedule_key: "future", next_run_at: at(1)}))

          assert store |> ScheduleStore.claim_due(at()) |> keys() ==
                   ["c-earlier", "a-due", "b-due"]

          assert ScheduleStore.get_schedule(store, "future").next_run_at == at(1)
          assert [%{schedule_key: "future"}] = ScheduleStore.claim_due(store, at(1))
        end

        test "a slot already claimed is not claimed again and leaves the schedule in place",
             %{store: store} do
          put_schedule(store, schedule())
          [_claimed] = ScheduleStore.claim_due(store, at())
          put_schedule(store, schedule(%{claimed_occurrences: 1}))

          assert ScheduleStore.claim_due(store, at()) == []

          assert ScheduleStore.get_schedule(store, "contract-daily") ==
                   schedule(%{claimed_occurrences: 1})
        end

        test "a schedule expires at its final occurrence and an ineligible one expires unclaimed",
             %{store: store} do
          put_schedule(
            store,
            schedule(%{
              schedule_key: "last",
              expiration_kind: "after_occurrences",
              max_occurrences: 2,
              claimed_occurrences: 1
            })
          )

          put_schedule(
            store,
            schedule(%{schedule_key: "lapsed", expiration_kind: "at", expires_at: slot()})
          )

          put_schedule(
            store,
            schedule(%{schedule_key: "until", expiration_kind: "at", expires_at: at(1)})
          )

          assert [%{schedule_key: "last", occurrence_number: 2}, %{schedule_key: "until"}] =
                   ScheduleStore.claim_due(store, at())

          assert %{expired_at: expired_at, claimed_occurrences: 2, next_run_at: next_run_at} =
                   ScheduleStore.get_schedule(store, "last")

          assert {expired_at, next_run_at} == {at(), next_slot()}

          assert ScheduleStore.get_schedule(store, "lapsed") ==
                   schedule(%{
                     schedule_key: "lapsed",
                     expiration_kind: "at",
                     expires_at: slot(),
                     expired_at: at(),
                     updated_at: at()
                   })

          assert ScheduleStore.get_schedule(store, "until").expired_at == nil

          # A day later "until" has lapsed too: no schedule claims the next slot.
          later = ScheduleStore.claim_due(store, at(86_400))
          assert Enum.filter(later, &(&1.scheduled_for == next_slot())) == []
          assert ScheduleStore.get_schedule(store, "until").expired_at == at(86_400)
        end
      end

      ScheduleStoreContract.setup_and_retry_cases()
      ScheduleStoreContract.run_result_cases()
      ScheduleStoreContract.verified_run_cases()
      ScheduleStoreContract.schedule_edit_cases()
    end
  end

  @doc """
  The cases pinning setup claims, failed attempts, expired leases and the order runs are recovered in, injected by `using/1` (kept apart so no quote grows past a readable
  length). They rely on the caller's `put_schedule/2` and the `store` from the template's
  setup.
  """
  defmacro setup_and_retry_cases do
    quote do
      describe "ScheduleStore setup and retry contract" do
        test "a setup claim is idempotent per claim key", %{store: store} do
          put_schedule(store, schedule(%{schedule_key: "backup", revision: 3}))

          first = ScheduleStore.claim_setup(store, "backup", "setup:destination", at())

          assert %{
                   claim_key: "setup:destination",
                   claim_kind: "setup",
                   scheduled_for: nil,
                   schedule_revision: 3,
                   occurrence_number: nil,
                   attempt: 1,
                   state: "running",
                   lease_expires_at: lease,
                   started_at: started_at
                 } = first

          assert {lease, started_at} == {at(15 * 60), at()}
          assert ScheduleStore.claim_setup(store, "backup", "setup:destination", at(60)) == first

          other = ScheduleStore.claim_setup(store, "backup", "setup:other", at())
          assert other.run_id != first.run_id
          assert ScheduleStore.claim_due(store, at()) |> keys() == ["backup"]
        end

        test "a setup claim for an unknown schedule raises", %{store: store} do
          assert_raise RuntimeError, ~r/unknown schedule/, fn ->
            ScheduleStore.claim_setup(store, "missing", "setup:destination", at())
          end
        end

        test "a failed attempt waits as retryable under its occurrence and fails at the third",
             %{store: store} do
          put_schedule(store, schedule())
          [%{run_id: run_id}] = ScheduleStore.claim_due(store, at())

          assert {:retryable, retry} =
                   ScheduleStore.fail_attempt(store, run_id, 1, :capacity, at())

          assert Map.take(retry, [
                   :run_id,
                   :state,
                   :attempt,
                   :occurrence_number,
                   :lease_expires_at,
                   :next_attempt_at,
                   :failure_category,
                   :finished_at
                 ]) == %{
                   run_id: run_id,
                   state: "retryable",
                   attempt: 2,
                   occurrence_number: 1,
                   lease_expires_at: nil,
                   next_attempt_at: at(5 * 60),
                   failure_category: "capacity",
                   finished_at: at()
                 }

          assert ScheduleStore.claim_due(store, at(5 * 60 - 1)) == []

          assert [%{run_id: ^run_id} = again] = ScheduleStore.claim_due(store, at(5 * 60))

          assert Map.take(again, [:state, :attempt, :lease_expires_at, :next_attempt_at]) ==
                   %{
                     state: "running",
                     attempt: 2,
                     lease_expires_at: at(20 * 60),
                     next_attempt_at: nil
                   }

          assert {again.failure_category, again.started_at, again.finished_at} ==
                   {nil, at(5 * 60), nil}

          assert {:retryable, %{attempt: 3, next_attempt_at: third_at}} =
                   ScheduleStore.fail_attempt(store, run_id, 2, :capacity, at(5 * 60))

          assert third_at == at(35 * 60)
          assert [%{run_id: ^run_id, attempt: 3}] = ScheduleStore.claim_due(store, at(35 * 60))

          assert {:failed, failed} =
                   ScheduleStore.fail_attempt(store, run_id, 3, :timeout, at(36 * 60))

          assert Map.take(failed, [
                   :state,
                   :attempt,
                   :occurrence_number,
                   :lease_expires_at,
                   :next_attempt_at,
                   :failure_category,
                   :finished_at
                 ]) == %{
                   state: "failed",
                   attempt: 3,
                   occurrence_number: 1,
                   lease_expires_at: nil,
                   next_attempt_at: nil,
                   failure_category: "timeout",
                   finished_at: at(36 * 60)
                 }

          assert ScheduleStore.claim_due(store, at(3_600)) == []
        end

        test "a lease that expired runs again under the next attempt, up to the attempt limit",
             %{store: store} do
          put_schedule(store, schedule())
          [%{run_id: run_id}] = ScheduleStore.claim_due(store, at())

          assert ScheduleStore.claim_due(store, at(15 * 60 - 1)) == []

          assert [%{run_id: ^run_id, attempt: 2, state: "running"} = second] =
                   ScheduleStore.claim_due(store, at(15 * 60))

          assert {second.lease_expires_at, second.started_at} == {at(30 * 60), at(15 * 60)}
          assert [%{run_id: ^run_id, attempt: 3}] = ScheduleStore.claim_due(store, at(30 * 60))
          assert ScheduleStore.claim_due(store, at(45 * 60)) == []

          assert %{
                   last_run_state: "failed",
                   last_failure_category: "attempt_limit",
                   last_finished_at: finished_at
                 } = row(store, "contract-daily")

          assert finished_at == at(45 * 60)
          assert ScheduleStore.claim_due(store, at(3_600)) == []
        end

        test "recovers retryable and expired runs in start order", %{store: store} do
          put_schedule(store, schedule(%{schedule_key: "z-earlier"}))
          [_earlier] = ScheduleStore.claim_due(store, at())
          put_schedule(store, schedule(%{schedule_key: "a-later", next_run_at: at(60)}))
          [later] = ScheduleStore.claim_due(store, at(60))
          {:retryable, _retry} = ScheduleStore.fail_attempt(store, later.run_id, 1, :io, at(60))

          assert store |> ScheduleStore.claim_due(at(16 * 60)) |> keys() ==
                   ["z-earlier", "a-later"]
        end
      end
    end
  end

  @doc """
  The cases pinning the running attempt's lease and result, and the inventory, injected by `using/1` (kept apart so no quote grows past a readable
  length). They rely on the caller's `put_schedule/2` and the `store` from the template's
  setup.
  """
  defmacro run_result_cases do
    quote do
      describe "ScheduleStore run result and inventory contract" do
        test "only the running attempt renews, stays active, completes or skips",
             %{store: store} do
          put_schedule(store, schedule())
          [%{run_id: run_id}] = ScheduleStore.claim_due(store, at())
          stale = {:error, :stale_attempt}

          assert ScheduleStore.renew_lease(store, run_id, 2, at(60)) == stale
          assert ScheduleStore.renew_lease(store, run_id, 1, at(60)) == :ok
          assert ScheduleStore.active_attempt?(store, run_id, 1, at(15 * 60))
          refute ScheduleStore.active_attempt?(store, run_id, 1, at(16 * 60))
          refute ScheduleStore.active_attempt?(store, run_id, 2, at())

          receipt = %{
            "artifactBasename" => "bnest-contract.sqlite3",
            "artifactSha256" => String.duplicate("a", 64),
            "artifactBytes" => 42
          }

          assert ScheduleStore.complete(store, run_id, 2, receipt, at(120)) == stale
          assert ScheduleStore.complete(store, run_id, 1, receipt, at(120)) == :ok
          refute ScheduleStore.active_attempt?(store, run_id, 1, at(120))
          assert ScheduleStore.complete(store, run_id, 1, receipt, at(180)) == stale
          assert ScheduleStore.skip(store, run_id, 1, :destination_changed, at(180)) == stale
          assert ScheduleStore.renew_lease(store, run_id, 1, at(180)) == stale
          assert ScheduleStore.fail_attempt(store, run_id, 1, :io, at(180)) == stale

          assert %{
                   last_run_state: "verified",
                   last_failure_category: nil,
                   last_finished_at: completed_at
                 } = row(store, "contract-daily")

          assert completed_at == at(120)

          put_schedule(store, schedule(%{schedule_key: "moved"}))
          skipped = ScheduleStore.claim_setup(store, "moved", "setup:old", at())

          assert ScheduleStore.skip(store, skipped.run_id, 1, :destination_changed, at(60)) ==
                   :ok

          assert ScheduleStore.skip(store, skipped.run_id, 1, :destination_changed, at(60)) ==
                   stale

          assert %{last_run_state: "skipped", last_failure_category: "destination_changed"} =
                   row(store, "moved")
        end

        test "inventory lists every schedule by context then key with its latest run",
             %{store: store} do
          put_schedule(store, schedule(%{schedule_key: "b-family", next_run_at: at(3_600)}))

          put_schedule(
            store,
            schedule(%{schedule_key: "a-family", next_run_at: at(3_600), revision: 2})
          )

          put_schedule(
            store,
            schedule(%{
              schedule_key: "z-admin",
              schedule_context: "admin_system",
              handler_key: "prod_sqlite_backup",
              next_run_at: at(3_600)
            })
          )

          ScheduleStore.claim_setup(store, "a-family", "setup:one", at())
          latest = ScheduleStore.claim_setup(store, "a-family", "setup:two", at(60))

          inventory = ScheduleStore.inventory(store)
          assert keys(inventory) == ["z-admin", "a-family", "b-family"]

          for row <- inventory do
            schedule = ScheduleStore.get_schedule(store, row.schedule_key)
            assert Map.take(row, Map.keys(schedule)) == schedule
          end

          assert Map.take(row(store, "a-family"), [
                   :last_run_state,
                   :last_failure_category,
                   :last_finished_at
                 ]) == %{
                   last_run_state: "running",
                   last_failure_category: nil,
                   last_finished_at: nil
                 }

          assert %{last_run_state: nil, last_failure_category: nil, last_finished_at: nil} =
                   row(store, "b-family")

          {:retryable, _retry} =
            ScheduleStore.fail_attempt(store, latest.run_id, 1, :capacity, at(120))

          assert %{last_run_state: "retryable", last_failure_category: "capacity"} =
                   row(store, "a-family")

          assert row(store, "a-family").last_finished_at == at(120)
        end
      end
    end
  end

  @doc """
  The cases pinning `verified_runs/2`, the verified runs of a handler's schedules, injected
  by `using/1` (kept apart so no quote grows past a readable length). They rely on the
  caller's `put_schedule/2` and the `store` from the template's setup.
  """
  defmacro verified_run_cases do
    quote do
      describe "ScheduleStore verified runs contract" do
        test "lists a handler's verified runs oldest finish first, leaving out every other state",
             %{store: store} do
          backup = %{schedule_context: "admin_system", handler_key: "prod_sqlite_backup"}
          put_schedule(store, schedule(Map.put(backup, :schedule_key, "backup-daily")))
          put_schedule(store, schedule(Map.put(backup, :schedule_key, "backup-failing")))
          put_schedule(store, schedule(%{schedule_key: "other-daily"}))

          [daily, failing, other] = ScheduleStore.claim_due(store, at())

          assert keys([daily, failing, other]) == [
                   "backup-daily",
                   "backup-failing",
                   "other-daily"
                 ]

          setup_verified =
            ScheduleStore.claim_setup(store, "backup-daily", "setup:verified", at(60))

          setup_skipped =
            ScheduleStore.claim_setup(store, "backup-daily", "setup:skipped", at(60))

          :ok = ScheduleStore.complete(store, setup_verified.run_id, 1, receipt("setup"), at(120))
          :ok = ScheduleStore.skip(store, setup_skipped.run_id, 1, :destination_changed, at(130))
          :ok = ScheduleStore.complete(store, daily.run_id, 1, receipt("night"), at(300))
          :ok = ScheduleStore.complete(store, other.run_id, 1, receipt("other"), at(300))

          # The failing run loses its lease at every attempt and ends failed; a setup run is
          # then claimed and left running.
          for seconds <- [15 * 60, 30 * 60, 45 * 60],
              do: ScheduleStore.claim_due(store, at(seconds))

          assert %{last_run_state: "failed"} = row(store, "backup-failing")

          assert %{state: "running"} =
                   ScheduleStore.claim_setup(store, "backup-daily", "setup:running", at(46 * 60))

          before = ScheduleStore.inventory(store)

          # The setup run, claimed without a slot, finished first; the nightly run followed.
          assert ScheduleStore.verified_runs(store, "prod_sqlite_backup") == [
                   verified_view(setup_verified.run_id, nil, at(120), "setup"),
                   verified_view(daily.run_id, slot(), at(300), "night")
                 ]

          assert ScheduleStore.verified_runs(store, "fixture") ==
                   [verified_view(other.run_id, slot(), at(300), "other")]

          assert ScheduleStore.inventory(store) == before
        end

        test "reports a verified setup run, claimed without a slot, with a nil slot",
             %{store: store} do
          put_schedule(
            store,
            schedule(%{
              schedule_key: "backup-setup",
              schedule_context: "admin_system",
              handler_key: "prod_sqlite_backup",
              next_run_at: at(86_400)
            })
          )

          setup_run = ScheduleStore.claim_setup(store, "backup-setup", "setup:destination", at())
          assert setup_run.scheduled_for == nil
          :ok = ScheduleStore.complete(store, setup_run.run_id, 1, receipt("setup"), at(60))

          assert ScheduleStore.verified_runs(store, "prod_sqlite_backup") ==
                   [verified_view(setup_run.run_id, nil, at(60), "setup")]
        end

        test "lists nothing for a handler with no verified run or no schedule", %{store: store} do
          put_schedule(
            store,
            schedule(%{
              schedule_key: "backup-running",
              schedule_context: "admin_system",
              handler_key: "prod_sqlite_backup"
            })
          )

          assert [%{state: "running"}] = ScheduleStore.claim_due(store, at())

          assert ScheduleStore.verified_runs(store, "prod_sqlite_backup") == []
          assert ScheduleStore.verified_runs(store, "unregistered") == []
        end
      end
    end
  end

  @doc """
  The cases pinning the daily update and the pristine convergence and activation, injected by `using/1` (kept apart so no quote grows past a readable
  length). They rely on the caller's `put_schedule/2` and the `store` from the template's
  setup.
  """
  defmacro schedule_edit_cases do
    quote do
      describe "ScheduleStore schedule edit contract" do
        test "a daily update applies only at the expected revision", %{store: store} do
          put_schedule(store, schedule(%{schedule_key: "edited"}))

          assert {:ok, updated} =
                   ScheduleStore.update_daily(store, "edited", "01:30", false, 1, at())

          assert updated ==
                   schedule(%{
                     schedule_key: "edited",
                     daily_at_utc: "01:30",
                     enabled: false,
                     next_run_at: ~U[2026-09-19 01:30:00Z],
                     revision: 2,
                     updated_at: at()
                   })

          assert ScheduleStore.get_schedule(store, "edited") == updated

          assert ScheduleStore.update_daily(store, "edited", "02:00", true, 1, at(60)) ==
                   {:error, :conflict}

          assert ScheduleStore.update_daily(store, "missing", "02:00", true, 1, at(60)) ==
                   {:error, :conflict}

          assert ScheduleStore.get_schedule(store, "edited") == updated
        end

        test "pristine convergence and activation take effect only at revision 1",
             %{store: store} do
          put_schedule(store, schedule(%{schedule_key: "backup", daily_at_utc: "23:00"}))

          put_schedule(
            store,
            schedule(%{schedule_key: "retention", daily_at_utc: "17:15", enabled: false})
          )

          put_schedule(store, schedule(%{schedule_key: "edited", revision: 2}))

          assert {:ok, converged} =
                   ScheduleStore.converge_daily_time_if_pristine!(store, "backup", "18:00", at())

          assert converged ==
                   schedule(%{
                     schedule_key: "backup",
                     daily_at_utc: "18:00",
                     next_run_at: ~U[2026-09-19 18:00:00Z],
                     revision: 2,
                     updated_at: at()
                   })

          assert ScheduleStore.converge_daily_time_if_pristine!(store, "backup", "06:00", at(60)) ==
                   {:ok, converged}

          assert ScheduleStore.converge_daily_time_if_pristine!(store, "edited", "18:00", at()) ==
                   {:ok, schedule(%{schedule_key: "edited", revision: 2})}

          assert ScheduleStore.activate_if_pristine!(store, "retention", at()) == :ok

          activated =
            schedule(%{
              schedule_key: "retention",
              daily_at_utc: "17:15",
              enabled: true,
              revision: 2,
              updated_at: at()
            })

          assert ScheduleStore.get_schedule(store, "retention") == activated
          assert ScheduleStore.activate_if_pristine!(store, "retention", at(60)) == :ok
          assert ScheduleStore.get_schedule(store, "retention") == activated
          assert ScheduleStore.activate_if_pristine!(store, "missing", at()) == :ok
          assert ScheduleStore.get_schedule(store, "missing") == nil

          assert_raise RuntimeError, ~r/unknown schedule/, fn ->
            ScheduleStore.converge_daily_time_if_pristine!(store, "missing", "18:00", at())
          end
        end
      end
    end
  end
end
