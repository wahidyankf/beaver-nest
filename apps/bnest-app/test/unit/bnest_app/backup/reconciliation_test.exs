defmodule BnestApp.Backup.ReconciliationTest do
  use ExUnit.Case, async: true

  alias BnestApp.Backup.Domain.Reconciliation
  alias BnestApp.Backup.Domain.Retention

  @label "Backup files"
  @could_not_check "could not be checked. Run mix bnest.backup.reconcile on the host."

  # A verified run finished at `finished_at`, one minute after its slot, with a synthetic
  # artifact named and digested after `name`.
  defp run(name, finished_at, fields \\ %{}) do
    Map.merge(
      %{
        run_id: "test-run-#{name}",
        slot: DateTime.add(finished_at, -60),
        finished_at: finished_at,
        artifact_basename: "bnest-prod-#{name}.sqlite3",
        artifact_sha256: digest(name),
        artifact_bytes: 4_096
      },
      fields
    )
  end

  # The nightly run of WIB date `date`: slot 19:00 UTC the day before, finished a minute later.
  defp nightly(date) do
    finished_at = DateTime.new!(Date.add(date, -1), ~T[19:01:00], "Etc/UTC")
    run(Date.to_iso8601(date, :basic), finished_at)
  end

  defp nightlies(count, first_date),
    do: for(offset <- 0..(count - 1)//1, do: nightly(Date.add(first_date, offset)))

  defp digest(name), do: Base.encode16(:crypto.hash(:sha256, to_string(name)), case: :lower)

  # What reading an intact artifact of each run from the destination reports.
  defp artifacts(runs),
    do:
      Map.new(runs, fn run ->
        {run.artifact_basename, %{sha256: run.artifact_sha256, bytes: run.artifact_bytes}}
      end)

  defp states(results), do: Enum.map(results, & &1.state)

  # The outcome of reconciling `count` consecutive WIB dates from 2030-05-12, `states` giving
  # the state of the date at each index (present unless named).
  defp outcome(count, states \\ %{}) do
    runs = nightlies(count, ~D[2030-05-12])

    observed =
      runs
      |> Enum.with_index()
      |> Enum.reduce(artifacts(runs), fn {run, index}, observed ->
        case Map.get(states, index, :present) do
          :present -> observed
          :missing -> Map.delete(observed, run.artifact_basename)
          :changed -> put_in(observed[run.artifact_basename][:sha256], digest("changed"))
        end
      end)

    {:ok, Reconciliation.classify(runs, observed)}
  end

  defp lines(outcome), do: outcome |> Reconciliation.report() |> Reconciliation.render()

  describe "classify/2" do
    test "reports a verified run whose artifact is not on disk as missing" do
      [first, second, third] = runs = nightlies(3, ~D[2030-05-14])

      assert Reconciliation.classify(runs, Map.delete(artifacts(runs), third.artifact_basename)) ==
               [
                 %{
                   date: ~D[2030-05-14],
                   slot: first.slot,
                   artifact_basename: first.artifact_basename,
                   state: :present
                 },
                 %{
                   date: ~D[2030-05-15],
                   slot: second.slot,
                   artifact_basename: second.artifact_basename,
                   state: :present
                 },
                 %{
                   date: ~D[2030-05-16],
                   slot: third.slot,
                   artifact_basename: third.artifact_basename,
                   state: :missing
                 }
               ]
    end

    test "reports an artifact whose digest or size differs from the ledger as changed" do
      [intact, rewritten, truncated] = runs = nightlies(3, ~D[2030-05-14])

      observed =
        runs
        |> artifacts()
        |> put_in([rewritten.artifact_basename, :sha256], digest("rewritten"))
        |> put_in([truncated.artifact_basename, :bytes], 1)

      assert runs
             |> Reconciliation.classify(observed)
             |> Map.new(&{&1.artifact_basename, &1.state}) ==
               %{
                 intact.artifact_basename => :present,
                 rewritten.artifact_basename => :changed,
                 truncated.artifact_basename => :changed
               }
    end

    test "does not expect a run older than the seven latest WIB dates" do
      [oldest | retained] = runs = nightlies(8, ~D[2030-05-11])

      # Retention removed the oldest pair, so no artifact of it is on disk.
      results = Reconciliation.classify(runs, artifacts(retained))

      assert [%{state: :not_expected, date: ~D[2030-05-11]} | rest] = results
      assert states(rest) == List.duplicate(:present, 7)
      assert hd(results).artifact_basename == oldest.artifact_basename
    end

    test "counts the seven latest dates that hold a run, not seven calendar days" do
      runs =
        for date <- [
              ~D[2030-05-01],
              ~D[2030-05-03] | Enum.map(1..6, &Date.add(~D[2030-05-10], &1 * 2))
            ],
            do: nightly(date)

      results = Reconciliation.classify(runs, artifacts(runs))

      assert [%{date: ~D[2030-05-01], state: :not_expected} | rest] = results
      assert states(rest) == List.duplicate(:present, 7)
    end

    test "expects only the newest of two verified runs on one WIB date" do
      older = run("older", ~U[2030-05-14 17:30:00Z])
      newer = run("newer", ~U[2030-05-15 10:00:00Z])

      # Both finished on WIB 2030-05-15 (00:30 and 17:00); only the newer artifact is on disk.
      assert [
               %{state: :not_expected, date: ~D[2030-05-15], artifact_basename: older_name},
               %{state: :present, date: ~D[2030-05-15], artifact_basename: newer_name}
             ] = Reconciliation.classify([newer, older], artifacts([newer]))

      assert {older_name, newer_name} == {older.artifact_basename, newer.artifact_basename}
    end

    test "leaves a superseded run not expected even when its artifact is on disk" do
      older = run("older", ~U[2030-05-14 17:30:00Z])
      newer = run("newer", ~U[2030-05-15 10:00:00Z])

      assert [:not_expected, :present] ==
               [older, newer] |> Reconciliation.classify(artifacts([older, newer])) |> states()
    end

    test "groups a run by finished_at, not by its slot, as Retention does its receipt" do
      # Slot 2030-05-14T16:59Z is WIB 23:59 on the 14th; it finished at 17:01Z, WIB 00:01 on the
      # 15th, which is the date Retention gives a receipt created then.
      late = run("late", ~U[2030-05-14 17:01:00Z], %{slot: ~U[2030-05-14 16:59:00Z]})
      same_date = run("same-date", ~U[2030-05-15 10:00:00Z])

      assert [
               %{state: :not_expected, date: ~D[2030-05-15], slot: ~U[2030-05-14 16:59:00Z]},
               %{state: :present, date: ~D[2030-05-15]}
             ] = Reconciliation.classify([late, same_date], artifacts([late, same_date]))

      # Retention agrees: of the two receipts of that date it keeps the same run.
      receipts =
        for run <- [same_date, late],
            do: %{"runId" => run.run_id, "createdAt" => DateTime.to_iso8601(run.finished_at)}

      assert Retention.retained_run_ids(receipts) == MapSet.new([same_date.run_id])

      assert Enum.map(Reconciliation.expected([late, same_date]), & &1.run_id) == [
               same_date.run_id
             ]
    end

    test "expects exactly the runs Retention keeps from their receipts" do
      runs =
        for day <- 0..11, offset <- [0, 90] do
          run(
            "#{day}-#{offset}",
            DateTime.add(~U[2030-05-01 03:00:00Z], day * 86_400 + offset * 60)
          )
        end

      receipts =
        for run <- runs,
            do: %{"runId" => run.run_id, "createdAt" => DateTime.to_iso8601(run.finished_at)}

      assert runs |> Reconciliation.expected() |> MapSet.new(& &1.run_id) ==
               Retention.retained_run_ids(Retention.newest_first(receipts))
    end

    test "reports a run with no slot, such as a setup run, on the date it finished" do
      setup_run = run("setup", ~U[2030-05-14 17:05:00Z], %{slot: nil})

      assert Reconciliation.classify([setup_run], artifacts([setup_run])) == [
               %{
                 date: ~D[2030-05-15],
                 slot: nil,
                 artifact_basename: setup_run.artifact_basename,
                 state: :present
               }
             ]
    end

    test "orders results by the date they are reported on, oldest first" do
      [first, second, third] = nightlies(3, ~D[2030-05-14])

      assert [~D[2030-05-14], ~D[2030-05-15], ~D[2030-05-16]] ==
               [third, first, second]
               |> Reconciliation.classify(%{})
               |> Enum.map(& &1.date)
    end

    test "reports nothing for a ledger with no verified run" do
      assert Reconciliation.classify([], %{}) == []
      assert Reconciliation.expected([]) == []
    end
  end

  describe "report/1 and render/1" do
    test "reads checking while a check runs, which is not a healthy outcome" do
      assert Reconciliation.report(:checking) == %{
               label: @label,
               summary: "checking",
               problems: [],
               footer: nil,
               exit_status: 1
             }

      assert lines(:checking) == ["Backup files: checking"]
    end

    test "states that every retained backup is present and exits zero" do
      assert Reconciliation.report(outcome(3)) == %{
               label: @label,
               summary: "all 3 retained backups are present",
               problems: [],
               footer: nil,
               exit_status: 0
             }

      assert lines(outcome(7)) == ["Backup files: all 7 retained backups are present"]
    end

    test "counts only the retained dates a verified run is expected on" do
      # Eight dates: the oldest is outside the window and is not counted.
      assert lines(outcome(8)) == ["Backup files: all 7 retained backups are present"]

      assert lines(outcome(8, %{0 => :missing})) == [
               "Backup files: all 7 retained backups are present"
             ]
    end

    test "uses the singular for one retained backup" do
      assert %{summary: "the retained backup is present", exit_status: 0} =
               Reconciliation.report(outcome(1))

      assert %{summary: "the retained backup needs attention", exit_status: 1} =
               Reconciliation.report(outcome(1, %{0 => :missing}))
    end

    test "counts the backups that need attention and names the date and state of each" do
      assert Reconciliation.report(outcome(7, %{2 => :missing, 4 => :changed})) == %{
               label: @label,
               summary: "2 of 7 retained backups need attention",
               problems: ["2030-05-14: file missing", "2030-05-16: file changed"],
               footer: nil,
               exit_status: 1
             }

      assert lines(outcome(7, %{2 => :missing, 4 => :changed})) == [
               "Backup files: 2 of 7 retained backups need attention",
               "2030-05-14: file missing",
               "2030-05-16: file changed"
             ]
    end

    test "uses the singular verb for one backup that needs attention" do
      assert lines(outcome(7, %{2 => :missing})) == [
               "Backup files: 1 of 7 retained backups needs attention",
               "2030-05-14: file missing"
             ]

      assert lines(outcome(7, %{6 => :changed})) == [
               "Backup files: 1 of 7 retained backups needs attention",
               "2030-05-18: file changed"
             ]
    end

    test "uses the plural verb when every one of several backups needs attention" do
      assert [summary | problems] = lines(outcome(2, %{0 => :missing, 1 => :changed}))
      assert summary == "Backup files: 2 of 2 retained backups need attention"
      assert problems == ["2030-05-12: file missing", "2030-05-13: file changed"]
    end

    test "lists the problems oldest date first whatever order the results arrive in" do
      {:ok, results} = outcome(7, %{5 => :changed, 1 => :missing, 3 => :missing})

      assert %{problems: ["2030-05-13: file missing" | _later] = problems} =
               Reconciliation.report({:ok, Enum.reverse(results)})

      assert problems == [
               "2030-05-13: file missing",
               "2030-05-15: file missing",
               "2030-05-17: file changed"
             ]
    end

    test "says plainly that the check could not run, whatever the reason" do
      reasons = [
        :ledger_unreadable,
        :ledger_unstable,
        :timeout,
        :raised,
        "/srv/test-user-backup/destination",
        %RuntimeError{message: "disk failure at /srv/test-user-backup/destination"}
      ]

      for reason <- reasons do
        assert Reconciliation.report({:error, reason}) == %{
                 label: @label,
                 summary: @could_not_check,
                 problems: [],
                 footer: nil,
                 exit_status: 1
               }

        assert lines({:error, reason}) == ["Backup files: " <> @could_not_check]
      end
    end

    test "says there is nothing to check for a ledger with no verified run" do
      assert Reconciliation.report({:ok, []}) == %{
               label: @label,
               summary: "no verified backup to check yet",
               problems: [],
               footer: nil,
               exit_status: 1
             }

      assert lines({:ok, []}) == ["Backup files: no verified backup to check yet"]

      # Results that expect nothing say the same: a run outside the window is not counted.
      superseded = %{
        date: ~D[2030-05-12],
        slot: nil,
        artifact_basename: "x",
        state: :not_expected
      }

      assert lines({:ok, [superseded]}) == ["Backup files: no verified backup to check yet"]

      refute Enum.any?(lines({:ok, []}), &(&1 =~ ~r/present|all \d/i))
    end

    test "renders the footer after the problems when a report carries one" do
      report = %{
        label: @label,
        summary: "1 of 3 retained backups needs attention",
        problems: ["2030-05-14: file missing"],
        footer: "A note for the reader",
        exit_status: 1
      }

      assert Reconciliation.render(report) == [
               "Backup files: 1 of 3 retained backups needs attention",
               "2030-05-14: file missing",
               "A note for the reader"
             ]
    end

    test "discloses no path, digest, destination identifier or run ID in any state" do
      {:ok, results} = outcome(7, %{1 => :missing, 3 => :changed})

      private =
        Enum.flat_map(
          nightlies(7, ~D[2030-05-12]),
          &[&1.run_id, &1.artifact_basename, &1.artifact_sha256]
        )

      for scenario <- [
            :checking,
            {:ok, []},
            {:ok, results},
            outcome(7),
            {:error, "/srv/test-user-backup/destination/run-id"}
          ] do
        output =
          scenario
          |> Reconciliation.report()
          |> inspect()
          |> Kernel.<>(Enum.join(lines(scenario), "\n"))

        # A report that said nothing would pass the refutations below vacuously.
        assert ["Backup files: " <> _summary | _problems] = lines(scenario)

        refute Enum.any?(private, &String.contains?(output, &1))
        refute output =~ ~r/[0-9a-f]{64}/
        refute output =~ ~r{(?:^|[\s"'(=:])/[\w.~-]}
        refute output =~ ".sqlite3"
      end
    end
  end
end
