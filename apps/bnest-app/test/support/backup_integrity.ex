defmodule BnestApp.Test.BackupIntegrity do
  @moduledoc """
  Test-only fixtures, operations and evidence for the backup-integrity scenarios of
  `scheduled_backups.feature`, shared by the unit and integration behaviour drivers.

  Nothing here is layer specific beyond the seams a Given needs: the layer is the one the
  adapters in `config :bnest_app, BnestApp.Backup` select (`in_memory?/0`). In the unit layer
  the ledger, the destination's files and its configuration live in the in-memory doubles; in
  the integration layer they are the isolated SQLite test database and a real temporary
  directory. Every operation and every check goes through the production facades
  (`BnestApp.Backup`, `BnestApp.Scheduler`) and the `ArtifactStore` port, so both layers
  exercise the same production calls:

    * a Given puts the ledger and the destination into a described state (`prepare/3`), the
      ledger through the test seams that stand in for rows no port callback writes
      (`BnestApp.Test.InMemory.ScheduleStore.put_run/2`,
      `BnestApp.Test.Seeds.Schedules.put_run!/1`), the destination through
      `Backup.record_receipt/4` and the port;
    * a When calls production code (`perform/3`, `run_task/2`): `Scheduler.verified_runs/1`,
      `Backup.reconcile/2`, `Backup.retain_owned/1`, `Scheduler.execute/2`, `Backup.destination/0`;
    * a Then reads the evidence back on its own (`outcome?/3`): the destination's files, the
      ledger's rows and the process table, never a value the When returned alone.

  Dates are WIB dates. A fixture run of WIB date `D` is a nightly run: slot 19:00 UTC on `D-1`,
  finished a minute later, so its WIB date is `D`.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Backup
  alias BnestApp.Backup.Domain.Receipt
  alias BnestApp.Backup.Ports.ArtifactStore
  alias BnestApp.Scheduler
  alias BnestApp.Test.InMemory.ArtifactStore, as: InMemoryArtifactStore
  alias BnestApp.Test.InMemory.BackupConfigStore, as: InMemoryBackupConfigStore
  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore
  alias BnestApp.Test.IntegrityLabel
  alias BnestApp.Test.ObservedArtifactStore
  alias BnestApp.Test.Seeds.Schedules
  alias BnestApp.Test.UnreadableArtifactStore
  alias BnestApp.Test.UnreadableLedger
  alias Mix.Tasks.Bnest.Backup.Reconcile

  @handler "prod_sqlite_backup"
  @ledger_schedule "bdd-integrity-ledger"
  @foreign_destination_id String.duplicate("F", 22)
  @eight_dates_from ~D[2030-05-11]
  @scheduled_slot ~U[2030-05-16 19:00:00Z]
  @scheduled_at ~U[2030-05-16 19:01:00Z]
  @retained_dates 7

  # The Schedules page's label is read against seven nightly runs from this WIB date; the
  # fixtures damage these dates (the newest, 2030-05-16, is read first and is the one a
  # blocked read waits on).
  @label_first_date ~D[2030-05-10]
  @label_missing_date "2030-05-12"
  @label_changed_date "2030-05-14"
  @label_newest_date "2030-05-16"
  @label_kinds ~w(all_present missing_and_changed two_problems missing missing_and_unknown raising ceiling watched)

  # Slot times of a run on WIB date `D`, all on `D-1` UTC: the nightly slot, an earlier run on
  # the same WIB date and a later one.
  @slot_times %{nightly: ~T[19:00:00], earlier: ~T[17:30:00], later: ~T[21:00:00]}

  @digest ~r/[0-9a-f]{64}/
  @absolute_path ~r{(?:^|[\s"'(=:])/[\w.~-]}
  @date_line ~r/\d{4}-\d{2}-\d{2}/
  @failure_line ~r/(reconcil|backup files|integrity)[^\n]*(could not|fail)|(could not|fail)[^\n]*(reconcil|backup files|integrity)/i

  # Givens that need the layer's isolated destination first (the driver establishes it).
  @destination_prepares [
    :integrity_ledger,
    :unreadable_ledger,
    :empty_ledger,
    :raising_reconciliation,
    :owned_pairs_for_eight_dates,
    :label_destination
  ]
  @prepares [
    :destination_holds_every_run,
    :pair_absent,
    :artifact_digest_differs,
    :pair_removed_by_retention,
    :older_run_without_files,
    :unknown_file,
    :foreign_and_unowned_files,
    :expected_artifact_removed,
    :test_environment
  ]
  @performs [
    :reconcile_ledger,
    :complete_scheduled_run,
    :run_retention,
    :resolve_default_directory
  ]
  @outcomes [
    :run_reported_missing,
    :runs_reported_present,
    :run_reported_changed,
    :run_not_reported,
    :other_runs_present,
    :newer_run_present,
    :older_run_not_reported,
    :destination_unchanged,
    :ledger_unchanged,
    :report_first_line,
    :report_no_problem_line,
    :report_problem_lines,
    :report_and_log_private_free,
    :run_verified_with_files,
    :reconciliation_failure_logged,
    :exit_zero_all_present,
    :report_no_date_line,
    :scheduler_not_started,
    :exit_nonzero,
    :report_names_problem,
    :report_private_free,
    :report_path_free_reason,
    :report_nothing_to_check,
    :report_nothing_present,
    :owned_pairs_outside_window_removed,
    :unowned_files_untouched,
    :foreign_receipts_never_counted,
    :default_directory_fails_closed,
    :default_directory_unchanged
  ]

  @doc "The Given states that run on a destination the driver has just established."
  @spec destination_prepares() :: [atom()]
  def destination_prepares, do: @destination_prepares

  @doc "The Given states that need no layer-specific step first."
  @spec prepares() :: [atom()]
  def prepares, do: @prepares

  @doc "The When actions that are the same production calls in both layers."
  @spec performs() :: [atom()]
  def performs, do: @performs

  @doc "The Then checks."
  @spec outcomes() :: [atom()]
  def outcomes, do: @outcomes

  # ---------------------------------------------------------------------------------------
  # Given
  # ---------------------------------------------------------------------------------------

  @doc "Puts the ledger and the destination into the state a Given describes."
  @spec prepare(map(), atom(), list()) :: map()
  def prepare(context, :integrity_ledger, [count, first_date]),
    do: seed_ledger(context, runs(count, Date.from_iso8601!(first_date)))

  # A ledger whose store cannot be opened, beside a destination that holds nothing.
  def prepare(context, :unreadable_ledger, []) do
    :ok = UnreadableLedger.install!()
    context
  end

  # A ledger that holds attempts but no verified one: a failed run is not a backup.
  def prepare(context, :empty_ledger, []) do
    clear_ledger()
    persist_schedule()
    failed = %{ledger_row(run(~D[2030-05-14], :nightly)) | state: "failed"}

    persist_run(%{
      failed
      | artifact_basename: nil,
        artifact_sha256: nil,
        artifact_bytes: nil,
        failure_category: "io_failed"
    })

    Map.put(context, :ledger_runs, [])
  end

  # The night before the scheduled run: its artifact sits in the destination without a receipt,
  # which backup, receipt writing and retention never read, and every read of it raises; so the
  # reconciliation after the run raises and nothing else fails.
  def prepare(context, :raising_reconciliation, []) do
    clear_ledger()
    persist_schedule()
    earlier = run(~D[2030-05-16], :nightly)
    persist_run(ledger_row(earlier))
    path = artifact_path(context, earlier)
    put_bytes(path, earlier.content)
    claim = running_claim()
    persist_run(claim)
    :ok = UnreadableArtifactStore.install!(path)

    Map.merge(context, %{
      ledger_runs: [earlier],
      scheduled_claim: claim,
      scheduled_at: @scheduled_at
    })
  end

  def prepare(context, :owned_pairs_for_eight_dates, []) do
    runs = runs(8, @eight_dates_from)
    Enum.each(runs, &write_pair(context, &1, context.backup_location))
    Map.put(context, :owned_runs, runs)
  end

  # The ledger and the destination the Schedules page's label is read against, one `kind` per
  # state the page scenarios describe. Seven nightly runs unless the kind says otherwise; a
  # kind installs the doubles it needs (an unreadable or observed artifact store) until the
  # calling test exits.
  def prepare(context, :label_destination, [kind]) when kind in @label_kinds,
    do: label_destination(context, kind)

  # The first of the seven dates loses its pair after the label has been read: one expected
  # artifact is then gone from the destination.
  def prepare(context, :expected_artifact_removed, []) do
    context = prepare(context, :pair_absent, [@label_missing_date])
    Map.put(context, :removed_date, @label_missing_date)
  end

  def prepare(context, :destination_holds_every_run, []) do
    Enum.each(context.ledger_runs, &write_pair(context, &1, context.backup_location))
    context
  end

  def prepare(context, :pair_absent, [date]) do
    remove_pair(context, nightly(context, date))
    context
  end

  def prepare(context, :artifact_digest_differs, [date]) do
    run = nightly(context, date)
    put_bytes(artifact_path(context, run), run.content <> " (changed)")

    if ArtifactStore.digest(artifact_store(), artifact_path(context, run)) == run.sha256,
      do: raise("the changed artifact kept its digest")

    context
  end

  # Absent because the production retention removed them, not because a test deleted them.
  def prepare(context, :pair_removed_by_retention, [date]) do
    run = nightly(context, date)
    {:ok, _kept} = Backup.retain_owned(context.backup_directory)

    if present?(context, run),
      do: raise("retention kept the pair of #{date}, which is inside the retained dates")

    context
  end

  def prepare(context, :older_run_without_files, [date]) do
    older = run(Date.from_iso8601!(date), :earlier)
    persist_run(ledger_row(older))
    Map.update!(context, :ledger_runs, &(&1 ++ [older]))
  end

  def prepare(context, :unknown_file, []) do
    put_bytes(Path.join(context.backup_directory, "unknown-note.txt"), "synthetic-unowned")
    context
  end

  # Receipts of another destination (one superseding an owned run's date, one newer than every
  # owned date), artifacts without a receipt, and a receipt that decodes but is no receipt.
  def prepare(context, :foreign_and_unowned_files, []) do
    foreign_location = %{
      directory: context.backup_directory,
      destination_id: @foreign_destination_id
    }

    foreign = [run(~D[2030-05-15], :later, :foreign), run(~D[2030-05-19], :nightly, :foreign)]
    Enum.each(foreign, &write_pair(context, &1, foreign_location))

    unreceipted = [
      run(~D[2030-05-12], :nightly, :unreceipted),
      run(~D[2030-05-18], :later, :unreceipted)
    ]

    Enum.each(unreceipted, &put_bytes(artifact_path(context, &1), &1.content))

    malformed = Path.join(context.backup_directory, "bnest-prod-malformed.sqlite3")
    put_bytes(malformed, "synthetic malformed pair")

    :ok =
      ArtifactStore.write_receipt(artifact_store(), Receipt.path(malformed), %{
        "schemaVersion" => 1
      })

    pairs =
      Enum.flat_map(
        foreign,
        &[artifact_path(context, &1), Receipt.path(artifact_path(context, &1))]
      )

    Map.put(
      context,
      :unowned_paths,
      pairs ++
        Enum.map(unreceipted, &artifact_path(context, &1)) ++ [malformed, Receipt.path(malformed)]
    )
  end

  # The test environment: the default destination, which the test configuration resolves,
  # lies in this run's own isolated root, so what the When does next cannot reach a real one.
  def prepare(context, :test_environment, []) do
    default = Backup.default_directory()

    unless isolated_default?(default),
      do: raise("the default backup directory is not inside this test run's isolated root")

    context
  end

  # ---------------------------------------------------------------------------------------
  # When
  # ---------------------------------------------------------------------------------------

  @doc "Calls the production code a When names, in the layer's configured adapters."
  @spec perform(map(), atom(), list()) :: map()
  def perform(context, :reconcile_ledger, []) do
    directory = context.backup_directory
    evidence = %{destination: snapshot(directory), ledger: ledger_rows()}
    runs = Scheduler.verified_runs(@handler)

    Map.merge(context, %{
      reconciliation: Backup.reconcile(directory, runs),
      evidence_before: evidence
    })
  end

  def perform(context, :complete_scheduled_run, []) do
    claim = context.scheduled_claim

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        _recorded = Scheduler.execute(claim, context.scheduled_at)
      end)

    Map.put(context, :scheduled_log, log)
  end

  def perform(context, :run_retention, []) do
    before = snapshot(context.backup_directory)
    {:ok, kept} = Backup.retain_owned(context.backup_directory)
    Map.put(context, :retention, %{before: before, kept: kept})
  end

  def perform(context, :resolve_default_directory, []) do
    default = Backup.default_directory()
    root = default |> Path.dirname() |> Path.dirname()
    before = %{root: snapshot(root), default: snapshot(default)}

    Map.put(context, :default_resolution, %{
      directory: default,
      root: root,
      before: before,
      result: Backup.destination()
    })
  end

  @doc """
  Runs the reconcile task through `task_fun`, which returns the task's `%{exit_status:, lines:}`,
  and records the Scheduler processes alive before it so a Then can compare them afterwards.
  """
  @spec run_task(map(), (-> map())) :: map()
  def run_task(context, task_fun) do
    schedulers = scheduler_pids()
    Map.merge(context, %{task: task_fun.(), scheduler_before: schedulers})
  end

  @doc """
  Reads the task's printed report, then lets the next nightly run complete in the same
  destination, which reconciles after its retention and logs; the log is captured.
  """
  @spec read_report_and_log(map(), (-> map())) :: map()
  def read_report_and_log(context, task_fun) do
    claim = running_claim()
    persist_run(claim)

    context
    |> run_task(task_fun)
    |> Map.merge(%{scheduled_claim: claim, scheduled_at: @scheduled_at})
    |> perform(:complete_scheduled_run, [])
  end

  # ---------------------------------------------------------------------------------------
  # Then
  # ---------------------------------------------------------------------------------------

  @doc "Whether the evidence a Then reads confirms what it states."
  @spec outcome?(map(), atom(), list()) :: boolean()
  def outcome?(context, :run_reported_missing, [date]) do
    run = nightly(context, date)
    reported?(context, run, :missing) and not on_disk?(context, run)
  end

  def outcome?(context, :runs_reported_present, dates) do
    dates
    |> Enum.map(&nightly(context, &1))
    |> Enum.all?(&(reported?(context, &1, :present) and intact?(context, &1)))
  end

  def outcome?(context, :run_reported_changed, [date]) do
    run = nightly(context, date)
    reported?(context, run, :changed) and on_disk?(context, run) and not intact?(context, run)
  end

  def outcome?(context, :run_not_reported, [date]),
    do: not reported_at_all?(context, nightly(context, date))

  def outcome?(context, :other_runs_present, [count]) do
    present = Enum.filter(results(context), &(&1.state == :present))

    length(present) == count and
      Enum.all?(present, fn result ->
        run = Enum.find(context.ledger_runs, &(&1.basename == result.artifact_basename))
        run != nil and result.date == run.date and intact?(context, run)
      end)
  end

  def outcome?(context, :newer_run_present, [date]) do
    run = nightly(context, date)
    reported?(context, run, :present) and intact?(context, run)
  end

  def outcome?(context, :older_run_not_reported, [date]),
    do: not reported_at_all?(context, older(context, date))

  def outcome?(context, :destination_unchanged, []),
    do: snapshot(context.backup_directory) == context.evidence_before.destination

  def outcome?(context, :ledger_unchanged, []),
    do: ledger_rows() == context.evidence_before.ledger

  def outcome?(context, :report_first_line, [line]), do: first_line(context) == line

  def outcome?(context, :report_no_problem_line, []),
    do: lines(context) != [] and tl(lines(context)) == []

  def outcome?(context, :report_problem_lines, problems),
    do: lines(context) != [] and tl(lines(context)) == problems

  # The printed report and the post-run log, each non-empty, each free of a private value. A
  # log with no error line would pass vacuously, so one must exist.
  def outcome?(context, :report_and_log_private_free, []) do
    log = context.scheduled_log

    lines(context) != [] and error_lines(log) != [] and
      not leaks?(Enum.join(lines(context), "\n"), context) and not leaks?(log, context)
  end

  def outcome?(context, :run_verified_with_files, []) do
    claim = context.scheduled_claim

    case Enum.find(ledger_rows(), &(&1.run_id == claim.run_id)) do
      %{state: "verified", artifact_basename: basename} when is_binary(basename) ->
        path = Path.join(context.backup_directory, basename)

        ArtifactStore.regular?(artifact_store(), path) and
          ArtifactStore.regular?(artifact_store(), Receipt.path(path))

      _not_verified ->
        false
    end
  end

  def outcome?(context, :reconciliation_failure_logged, []) do
    case error_lines(context.scheduled_log) do
      [line] -> Regex.match?(@failure_line, line) and not leaks?(context.scheduled_log, context)
      _none_or_several -> false
    end
  end

  def outcome?(context, :exit_zero_all_present, []) do
    expected = min(@retained_dates, length(Enum.uniq_by(context.ledger_runs, & &1.date)))

    context.task.exit_status == 0 and
      first_line(context) == "Backup files: all #{expected} retained backups are present"
  end

  def outcome?(context, :report_no_date_line, []),
    do: lines(context) != [] and not Enum.any?(lines(context), &Regex.match?(@date_line, &1))

  def outcome?(context, :scheduler_not_started, []),
    do: scheduler_pids() == context.scheduler_before

  def outcome?(context, :exit_nonzero, []),
    do: is_integer(context.task.exit_status) and context.task.exit_status != 0

  def outcome?(context, :report_names_problem, [date, state]),
    do:
      Enum.any?(lines(context), &(String.starts_with?(&1, date) and String.contains?(&1, state)))

  def outcome?(context, :report_private_free, []),
    do: lines(context) != [] and not leaks?(Enum.join(lines(context), "\n"), context)

  def outcome?(context, :report_path_free_reason, []),
    do:
      String.starts_with?(first_line(context), "Backup files: could not be checked") and
        not leaks?(Enum.join(lines(context), "\n"), context)

  def outcome?(context, :report_nothing_to_check, []),
    do: Enum.any?(lines(context), &String.contains?(&1, "no verified backup to check yet"))

  def outcome?(context, :report_nothing_present, []),
    do:
      lines(context) != [] and
        not Enum.any?(lines(context), &(Regex.match?(@date_line, &1) or &1 =~ ~r/present/i))

  # The oldest of eight owned dates is the only pair that left the destination, and the seven
  # latest remain whole.
  def outcome?(context, :owned_pairs_outside_window_removed, []) do
    {[oldest], retained} =
      context.owned_runs |> Enum.sort_by(& &1.date, {:asc, Date}) |> Enum.split(1)

    before = Map.keys(context.retention.before.entries)
    removed = before -- Map.keys(snapshot(context.backup_directory).entries)

    Enum.sort(removed) ==
      Enum.sort([artifact_path(context, oldest), Receipt.path(artifact_path(context, oldest))]) and
      length(retained) == @retained_dates and Enum.all?(retained, &present?(context, &1))
  end

  def outcome?(context, :unowned_files_untouched, []) do
    after_entries = snapshot(context.backup_directory).entries

    context.unowned_paths != [] and
      Enum.all?(context.unowned_paths, fn path ->
        match?({:ok, _entry}, Map.fetch(after_entries, path)) and
          Map.fetch(after_entries, path) == Map.fetch(context.retention.before.entries, path)
      end)
  end

  # The owned run of the date a newer foreign receipt shares is the one kept, and the kept set
  # is the owned runs of the seven latest owned dates, whatever the foreign receipts say.
  def outcome?(context, :foreign_receipts_never_counted, []) do
    latest =
      context.owned_runs |> Enum.sort_by(& &1.date, {:desc, Date}) |> Enum.take(@retained_dates)

    superseded = Enum.find(context.owned_runs, &(&1.date == ~D[2030-05-15]))

    context.retention.kept == MapSet.new(latest, & &1.run_id) and present?(context, superseded)
  end

  def outcome?(context, :default_directory_fails_closed, []) do
    resolution = context.default_resolution

    match?({:error, _reason}, resolution.result) and
      snapshot(resolution.root) == resolution.before.root and
      not snapshot(resolution.directory).present?
  end

  def outcome?(context, :default_directory_unchanged, []) do
    resolution = context.default_resolution
    snapshot(resolution.directory) == resolution.before.default
  end

  # ---------------------------------------------------------------------------------------
  # Operations and evidence the layers share
  # ---------------------------------------------------------------------------------------

  @doc """
  Everything under `directory`, by path: a file's content (and, in memory, its mode and
  flush) or `:directory`. Two snapshots are equal when nothing there changed.
  """
  @spec snapshot(String.t()) :: %{present?: boolean(), entries: map()}
  def snapshot(directory),
    do: if(in_memory?(), do: memory_snapshot(directory), else: disk_snapshot(directory))

  @doc "Every run row of the ledger, in a stable order, as the layer's store holds it."
  @spec ledger_rows() :: [map()]
  def ledger_rows do
    if in_memory?(),
      do: Enum.sort_by(InMemoryScheduleStore.runs(Scheduler.store()), & &1.run_id),
      else: Schedules.runs()
  end

  @doc "The processes of the Scheduler's coordinator and task supervisor (`nil` when absent)."
  @spec scheduler_pids() :: [pid() | nil]
  def scheduler_pids,
    do: Enum.map([BnestApp.Scheduler, BnestApp.Scheduler.Tasks], &Process.whereis/1)

  @doc """
  What the destination really holds of the runs retention keeps a backup for, read from its
  files and never from reconciliation: how many runs are expected, each problem as the date
  and state a surface prints for it, oldest first, and how many are intact. It assumes one run
  per WIB date, as the label fixtures seed.
  """
  @spec expected_label(map()) :: %{
          total: non_neg_integer(),
          problems: [String.t()],
          intact: non_neg_integer()
        }
  def expected_label(context) do
    states =
      context.ledger_runs
      |> Enum.sort_by(& &1.date, {:desc, Date})
      |> Enum.take(@retained_dates)
      |> Enum.sort_by(& &1.date, Date)
      |> Enum.map(&{&1, disk_state(context, &1)})

    %{
      total: length(states),
      problems: for({run, state} <- states, state != :present, do: problem_line(run.date, state)),
      intact: Enum.count(states, &(elem(&1, 1) == :present))
    }
  end

  @doc "Whether `text` carries a private value of this scenario's destination or ledger."
  @spec leaks_private_value?(map(), String.t()) :: boolean()
  def leaks_private_value?(context, text), do: leaks?(text, context)

  @doc """
  Puts the routed browser run's ledger and its configured destination into the state `kind`
  describes (`all_present`, `missing_and_changed` or `two_problems`) and returns what the
  journey asserts on: the expected run count, each problem line, and the private values no
  page may show. It runs in the live mix, over the run's own SQLite database and isolated
  destination, never the operator's.
  """
  @spec seed_for_browser!(String.t()) :: map()
  def seed_for_browser!(kind) do
    {:ok, location} = Backup.destination()

    %{backup_directory: location.directory, backup_location: location}
    |> prepare(:label_destination, [kind])
    |> browser_facts()
  end

  @doc """
  Removes the pair of `date` from the routed browser run's destination, as a retention
  mishap or a stray delete would, and returns the facts as `seed_for_browser!/1` does. The
  ledger is the seven nights of `all_present`.
  """
  @spec remove_for_browser!(String.t()) :: map()
  def remove_for_browser!(date) do
    {:ok, location} = Backup.destination()

    %{
      backup_directory: location.directory,
      backup_location: location,
      ledger_runs: runs(@retained_dates, @label_first_date)
    }
    |> prepare(:pair_absent, [date])
    |> browser_facts()
  end

  @doc """
  The reconcile task's printed lines over the routed browser run's ledger and destination, as
  the host operator would read them: a journey compares the page's label with them.
  """
  @spec browser_report!() :: map()
  def browser_report!, do: %{"lines" => Reconcile.execute([]).lines}

  defp seed_ledger(context, runs) do
    clear_ledger()
    persist_schedule()
    Enum.each(runs, &persist_run(ledger_row(&1)))
    Map.put(context, :ledger_runs, runs)
  end

  defp label_destination(context, "all_present") do
    context
    |> seed_ledger(runs(@retained_dates, @label_first_date))
    |> prepare(:destination_holds_every_run, [])
  end

  defp label_destination(context, "missing_and_changed") do
    context
    |> label_destination("missing")
    |> prepare(:artifact_digest_differs, [@label_changed_date])
  end

  defp label_destination(context, "two_problems") do
    runs = runs(2, Date.add(Date.from_iso8601!(@label_newest_date), -1))

    context
    |> seed_ledger(runs)
    |> prepare(:destination_holds_every_run, [])
    |> prepare(:pair_absent, [Date.to_iso8601(hd(runs).date)])
    |> prepare(:artifact_digest_differs, [@label_newest_date])
  end

  defp label_destination(context, "missing") do
    context
    |> label_destination("all_present")
    |> prepare(:pair_absent, [@label_missing_date])
  end

  defp label_destination(context, "missing_and_unknown") do
    context |> label_destination("missing") |> prepare(:unknown_file, [])
  end

  # An expected artifact whose every read raises, as a disk read error would.
  defp label_destination(context, "raising") do
    context = label_destination(context, "all_present")
    :ok = UnreadableArtifactStore.install!(artifact_path(context, newest_label_run(context)))
    context
  end

  # A reconciliation that never finishes: reading the newest expected artifact waits for ever,
  # and the page's ceiling is lowered so that the scenario meets it.
  defp label_destination(context, "ceiling") do
    context = label_destination(context, "all_present")
    :ok = ObservedArtifactStore.install!(block: artifact_path(context, newest_label_run(context)))
    :ok = IntegrityLabel.lower_ceiling!()
    context
  end

  # A destination whose reads are counted and never blocked.
  defp label_destination(context, "watched") do
    context = label_destination(context, "all_present")
    :ok = ObservedArtifactStore.install!()
    context
  end

  defp newest_label_run(context), do: nightly(context, @label_newest_date)

  defp browser_facts(context) do
    label = expected_label(context)

    %{
      "total" => label.total,
      "problems" => label.problems,
      "privateValues" => private_values(context)
    }
  end

  defp disk_state(context, run) do
    cond do
      not on_disk?(context, run) -> :missing
      not intact?(context, run) -> :changed
      true -> :present
    end
  end

  defp problem_line(date, state), do: "#{Date.to_iso8601(date)}: file #{state}"

  defp runs(count, first_date) do
    for offset <- 0..(count - 1)//1, do: run(Date.add(first_date, offset), :nightly)
  end

  # A run of WIB `date` finished a minute after its slot; the content is its artifact's bytes
  # and the digest and size are those the layer's artifact store reports for it.
  defp run(date, kind, label \\ nil) do
    label = label || kind
    slot = DateTime.new!(Date.add(date, -1), Map.fetch!(@slot_times, kind), "Etc/UTC")
    finished_at = DateTime.add(slot, 60)
    tag = "#{label}-#{Date.to_iso8601(date, :basic)}"
    content = "synthetic backup #{tag}"
    stamp = Calendar.strftime(finished_at, "%Y%m%dT%H%M%SZ")

    Map.merge(
      %{
        date: date,
        kind: kind,
        slot: slot,
        finished_at: finished_at,
        run_id: "test-run-" <> tag,
        basename: "bnest-prod-#{stamp}-test-#{tag}.sqlite3",
        content: content
      },
      fingerprint(content)
    )
  end

  # The in-memory artifact store digests and sizes the term it holds (its moduledoc); a disk
  # store, the file's bytes.
  defp fingerprint(content) do
    bytes = if in_memory?(), do: :erlang.term_to_binary(content), else: content
    %{sha256: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower), bytes: byte_size(bytes)}
  end

  defp ledger_row(run) do
    %{
      schedule_key: @ledger_schedule,
      claim_key: "slot:" <> iso8601(run.slot),
      claim_kind: "scheduled",
      scheduled_for: run.slot,
      run_id: run.run_id,
      schedule_revision: 1,
      occurrence_number: 1,
      attempt: 1,
      state: "verified",
      lease_expires_at: nil,
      next_attempt_at: nil,
      artifact_basename: run.basename,
      artifact_sha256: run.sha256,
      artifact_bytes: run.bytes,
      failure_category: nil,
      started_at: run.slot,
      finished_at: run.finished_at
    }
  end

  # The nightly claim after the ledger's last night, running under a lease that outlasts the
  # scheduled run's clock.
  defp running_claim do
    %{
      schedule_key: @ledger_schedule,
      claim_key: "slot:" <> iso8601(@scheduled_slot),
      claim_kind: "scheduled",
      scheduled_for: @scheduled_slot,
      run_id: "test-run-scheduled-20300517",
      schedule_revision: 1,
      occurrence_number: 2,
      attempt: 1,
      state: "running",
      lease_expires_at: DateTime.add(@scheduled_at, 15 * 60),
      next_attempt_at: nil,
      artifact_basename: nil,
      artifact_sha256: nil,
      artifact_bytes: nil,
      failure_category: nil,
      started_at: @scheduled_at,
      finished_at: nil
    }
  end

  # A disabled backup schedule that owns the seeded runs, so no coordinator claims it.
  defp persist_schedule do
    schedule = %{
      schedule_key: @ledger_schedule,
      handler_key: @handler,
      schedule_context: "admin_system",
      cadence: "daily",
      daily_at_utc: "19:00",
      enabled: false,
      expiration_kind: "never",
      expires_at: nil,
      max_occurrences: nil,
      claimed_occurrences: 0,
      expired_at: nil,
      next_run_at: ~U[2031-01-01 19:00:00Z],
      revision: 1,
      inserted_at: ~U[2030-01-01 00:00:00Z],
      updated_at: ~U[2030-01-01 00:00:00Z]
    }

    if in_memory?(),
      do: InMemoryScheduleStore.put_schedule(Scheduler.store(), schedule),
      else: Schedules.put_schedule!(schedule)
  end

  defp persist_run(run) do
    if in_memory?(),
      do: InMemoryScheduleStore.put_run(Scheduler.store(), run),
      else: Schedules.put_run!(run)
  end

  # The integration database is shared by every scenario of a run, so a scenario's ledger
  # starts by dropping the backup runs earlier scenarios left; the unit store is its own.
  defp clear_ledger, do: if(in_memory?(), do: :ok, else: Schedules.clear_runs!(@handler))

  defp write_pair(context, run, location) do
    path = artifact_path(context, run)
    put_bytes(path, run.content)

    artifact = %{
      path: path,
      basename: run.basename,
      sha256: run.sha256,
      bytes: run.bytes,
      quick_check: "ok",
      schema_versions: [1],
      logical_proof_sha256: Base.encode16(:crypto.hash(:sha256, run.basename), case: :lower),
      source_generation: nil
    }

    {:ok, _receipt} =
      Backup.record_receipt(ledger_row(run), location, run.finished_at, artifact)

    :ok
  end

  defp remove_pair(context, run) do
    path = artifact_path(context, run)
    :ok = ArtifactStore.remove(artifact_store(), path)
    :ok = ArtifactStore.remove(artifact_store(), Receipt.path(path))
  end

  defp put_bytes(path, content) do
    if in_memory?(),
      do: InMemoryArtifactStore.put_file(InMemoryArtifactStore.new(), path, content),
      else: File.write!(path, content)
  end

  defp artifact_store, do: Backup.adapter(:artifact_store).new()

  defp artifact_path(context, run), do: Path.join(context.backup_directory, run.basename)

  defp in_memory?, do: Backup.adapter(:config_store) == InMemoryBackupConfigStore

  # The test run's own default destination: under the root the test configuration resolves.
  defp isolated_default?(directory) do
    if in_memory?() do
      root = InMemoryBackupConfigStore.repository_root(InMemoryBackupConfigStore.new())
      directory == Path.join(root, "data/backup") and String.starts_with?(root, "/srv/test-user-")
    else
      root = Application.get_env(:bnest_app, :backup_repository_root)

      is_binary(root) and directory == Path.join(root, "data/backup") and
        String.contains?(root, "/data/test/backup-repository/")
    end
  end

  defp memory_snapshot(directory) do
    store = InMemoryArtifactStore.new()

    directories =
      store |> InMemoryArtifactStore.directories() |> Enum.filter(&within?(&1, directory))

    files =
      Map.new(InMemoryArtifactStore.paths(store, directory), fn path ->
        {path, InMemoryArtifactStore.file(store, path)}
      end)

    %{
      present?: directories != [] or files != %{},
      entries: Map.merge(files, Map.new(directories, &{&1, :directory}))
    }
  end

  defp disk_snapshot(directory) do
    entries =
      Map.new(Path.wildcard(Path.join(directory, "**"), match_dot: true), fn path ->
        {path, if(File.dir?(path), do: :directory, else: File.read!(path))}
      end)

    %{present?: File.dir?(directory), entries: entries}
  end

  defp within?(path, directory),
    do: path == directory or String.starts_with?(path, directory <> "/")

  defp present?(context, run) do
    path = artifact_path(context, run)

    ArtifactStore.regular?(artifact_store(), path) and
      ArtifactStore.regular?(artifact_store(), Receipt.path(path))
  end

  defp on_disk?(context, run),
    do: ArtifactStore.regular?(artifact_store(), artifact_path(context, run))

  # On disk and byte-for-byte what the ledger recorded.
  defp intact?(context, run) do
    path = artifact_path(context, run)

    ArtifactStore.regular?(artifact_store(), path) and
      ArtifactStore.digest(artifact_store(), path) == run.sha256
  end

  defp results(context) do
    {:ok, results} = context.reconciliation
    results
  end

  defp reported?(context, run, state) do
    Enum.any?(results(context), fn result ->
      result.date == run.date and result.artifact_basename == run.basename and
        result.state == state
    end)
  end

  defp reported_at_all?(context, run) do
    Enum.any?(results(context), fn result ->
      result.artifact_basename == run.basename and result.state in [:present, :missing, :changed]
    end)
  end

  defp nightly(context, date), do: find_run!(context, date, :nightly)
  defp older(context, date), do: find_run!(context, date, :earlier)

  defp find_run!(context, date, kind) do
    day = Date.from_iso8601!(date)

    Enum.find(context.ledger_runs, &(&1.date == day and &1.kind == kind)) ||
      raise(ArgumentError, "the ledger holds no #{kind} run on #{date}")
  end

  defp lines(context), do: context.task.lines
  defp first_line(context), do: context |> lines() |> List.first()

  defp error_lines(log),
    do: log |> String.split("\n") |> Enum.filter(&String.contains?(&1, "[error]"))

  defp leaks?(text, context) do
    Enum.any?(private_values(context), &String.contains?(text, &1)) or
      Regex.match?(@digest, text) or Regex.match?(@absolute_path, text)
  end

  # The destination's path and identifier, and each run's ID, artifact name and digest: what a
  # report or a log line must never carry.
  defp private_values(context) do
    rows = if context[:scheduled_claim], do: ledger_rows(), else: []
    runs = Map.get(context, :ledger_runs, []) ++ Map.get(context, :owned_runs, [])

    ([context[:backup_directory], get_in(context, [:backup_location, :destination_id])] ++
       Enum.flat_map(runs, &[&1.run_id, &1.basename, &1.sha256]) ++
       Enum.flat_map(rows, &[&1.run_id, &1.artifact_basename, &1.artifact_sha256]))
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp iso8601(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
