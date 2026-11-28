defmodule BnestApp.ScheduledBackupTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BnestApp.Backup
  alias BnestApp.Backup.Adapters.ScheduledBackupTask
  alias BnestApp.Backup.Adapters.SqliteDatabaseSnapshot
  alias BnestApp.Backup.Domain.Receipt
  alias BnestApp.FamilyChat
  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.Scheduler
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Test.UnreadableArtifactStore
  alias BnestApp.TestBackupDestination
  alias BnestApp.TestRuntimeRoot

  @now ~U[2026-08-30 20:00:00Z]

  setup do
    runtime = TestRuntimeRoot.create!("scheduled-backup")
    database_directory = Path.join(runtime.sqlite_path, "database")
    temporary_root = canonical_temporary_root()
    backup_directory = Path.join(temporary_root, "bnest-backup-#{runtime.run_id}")
    config_path = Path.join(temporary_root, "bnest-backup-config-#{runtime.run_id}.json")
    storage_config_path = Path.join(runtime.path, "storage-config/storage.json")
    System.put_env("BNEST_BACKUP_CONFIG", config_path)
    System.put_env("BNEST_STORAGE_CONFIG", storage_config_path)
    {:ok, _storage} = Storage.persist_directory(database_directory)
    :ok = SqliteCoordinator.ensure_started!(Path.join(database_directory, "bnest.sqlite3"))
    :ok = PersistentSchedules.apply_and_verify!(@now)
    FileConfigStore.activate_sqlite_primary!()

    on_exit(fn ->
      SqliteCoordinator.stop()
      System.delete_env("BNEST_BACKUP_CONFIG")
      System.delete_env("BNEST_STORAGE_CONFIG")
      File.rm_rf(backup_directory)
      File.rm_rf(backup_directory <> "-second")
      File.rm(backup_directory <> "-link")
      File.rm(config_path)
      TestRuntimeRoot.cleanup!(runtime)
    end)

    %{backup_directory: backup_directory, runtime: runtime}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: A daily backup with no saved folder is written to the repository backup folder
  test "resolves the ignored default from the runtime repository checkout", context do
    repository = Path.join(context.runtime.path, "release-checkout")
    File.mkdir_p!(repository)
    File.write!(Path.join(repository, ".gitignore"), "/data/*\n")

    {_output, 0} =
      System.cmd("git", ["init", "--quiet", repository],
        env: TestBackupDestination.git_child_env()
      )

    previous_root = System.get_env("BNEST_REPOSITORY_ROOT")
    System.put_env("BNEST_REPOSITORY_ROOT", repository)
    # As in production, which never sets the test run's own `:backup_repository_root`, so the
    # deployment's `BNEST_REPOSITORY_ROOT` names the runtime checkout; here an isolated one.
    previous_setting = Application.fetch_env(:bnest_app, :backup_repository_root)
    Application.delete_env(:bnest_app, :backup_repository_root)

    on_exit(fn ->
      case previous_root do
        nil -> System.delete_env("BNEST_REPOSITORY_ROOT")
        root -> System.put_env("BNEST_REPOSITORY_ROOT", root)
      end

      with {:ok, setting} <- previous_setting,
           do: Application.put_env(:bnest_app, :backup_repository_root, setting)
    end)

    expected = Path.join(repository, "data/backup")
    assert Backup.default_directory() == expected
    assert {:ok, %{directory: ^expected}} = Backup.destination()
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: A scheduled backup produces a verified snapshot of the live database
  test "writes and independently verifies one private owned pair", context do
    assert {:ok, location} = Backup.save_destination(context.backup_directory)

    assert {:ok, claim} =
             Scheduler.claim_setup("prod-sqlite-backup-daily", location.destination_id, @now)

    assert {:ok, receipt} = ScheduledBackupTask.execute(claim, @now)
    assert receipt["quickCheck"] == "ok"
    assert File.exists?(Path.join(context.backup_directory, receipt["artifactBasename"]))
    refute inspect(receipt) =~ context.backup_directory

    # The artifact is the configured database's copy: an independent proof of the artifact matches the
    # receipt, and the live database's own proof matches both.
    artifact_path = Path.join(context.backup_directory, receipt["artifactBasename"])

    assert {:ok, proof} =
             SqliteDatabaseSnapshot.prove(SqliteDatabaseSnapshot.new(), artifact_path)

    assert receipt["logicalProofSha256"] == proof.logical_sha256

    assert {:ok, live} =
             SqliteDatabaseSnapshot.prove(
               SqliteDatabaseSnapshot.new(),
               SqliteRepo.main_database_path()
             )

    assert proof.logical_sha256 == live.logical_sha256
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A backup that runs too long is cancelled, leaves no file, and is tried again
  test "a backup that exceeds its timeout is cancelled, leaves no file, and stays retryable",
       context do
    previous = Application.get_env(:bnest_app, :backup_timeout_ms)
    Application.put_env(:bnest_app, :backup_timeout_ms, 1)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:bnest_app, :backup_timeout_ms),
        else: Application.put_env(:bnest_app, :backup_timeout_ms, previous)
    end)

    assert {:ok, location} = Backup.save_destination(context.backup_directory)

    {:ok, claim} =
      Scheduler.claim_setup("prod-sqlite-backup-daily", location.destination_id, @now)

    probes = Task.async(fn -> family_chat_probe_rounds(10) end)

    assert {:error, :timeout} = ScheduledBackupTask.execute(claim, @now)

    assert context.backup_directory
           |> File.ls!()
           |> Enum.filter(&String.contains?(&1, ".sqlite3")) == []

    assert %{completed: 10, failures: 0} = Task.await(probes)
  end

  # Authenticated family chat reads and sends through the facade, run beside the backup.
  defp family_chat_probe_rounds(count) do
    user = "test-user-backup-probe"
    :ok = FamilyChat.ensure_ready!()
    slug = FamilyChat.canonical_room_slug()

    Enum.reduce(1..count, %{completed: 0, failures: 0}, fn _round, acc ->
      sent = FamilyChat.send_message(user, slug, Ecto.UUID.generate(), "probe")
      read = FamilyChat.list_messages(user, slug, [])

      if match?({:ok, _}, sent) and match?({:ok, _}, read),
        do: %{acc | completed: acc.completed + 1},
        else: %{acc | failures: acc.failures + 1}
    end)
  end

  test "retains one owned pair per current seven WIB dates and preserves unknown files",
       context do
    assert {:ok, location} = Backup.save_destination(context.backup_directory)
    unknown = Path.join(context.backup_directory, "keep-me.txt")
    File.write!(unknown, "synthetic")

    Enum.each(0..8, fn days ->
      at = DateTime.add(@now, -days * 86_400)

      {:ok, claim} =
        Scheduler.claim_setup(
          "prod-sqlite-backup-daily",
          "#{location.destination_id}-#{days}",
          at
        )

      assert {:ok, _receipt} = ScheduledBackupTask.execute(claim, at)
    end)

    assert File.exists?(unknown)
    assert Backup.owned_receipts(context.backup_directory) |> length() == 7
  end

  test "a destination change skips a stale setup claim", context do
    assert {:ok, first} = Backup.save_destination(context.backup_directory)
    {:ok, claim} = Scheduler.claim_setup("prod-sqlite-backup-daily", first.destination_id, @now)
    second_directory = context.backup_directory <> "-second"
    assert {:ok, _second} = Backup.save_destination(second_directory)
    assert {:skipped, :destination_changed} = ScheduledBackupTask.execute(claim, @now)
    refute File.exists?(Path.join(second_directory, claim.run_id <> ".sqlite3"))
  end

  test "rejects relative, repository, config, source, and symlink destinations", context do
    assert {:error, :not_absolute} = Backup.validate_destination("relative/backup")

    # The repository is an isolated one, `<root>/data/backup` its default: the test run's own
    # root is never a checkout.
    default = TestBackupDestination.default_repository!("repository-path")

    repository_path =
      default |> Path.dirname() |> Path.dirname() |> Path.join("apps/bnest-app/data")

    assert {:error, :repository_path} = Backup.validate_destination(repository_path)

    config_directory = System.fetch_env!("BNEST_BACKUP_CONFIG") |> Path.dirname()
    assert {:error, :config_overlap} = Backup.validate_destination(config_directory)

    source_directory = FileConfigStore.resolved_database_path() |> Path.dirname()
    assert {:error, :source_overlap} = Backup.validate_destination(source_directory)

    link = context.backup_directory <> "-link"
    File.mkdir_p!(context.backup_directory)
    File.ln_s!(context.backup_directory, link)
    assert {:error, :symlink} = Backup.validate_destination(Path.join(link, "nested"))
  end

  # The reconciliation after a run: the destination is checked against the ledger once the run
  # is recorded and retention has run. It reports through one telemetry event and one log
  # entry, names a run by its WIB date and state only, and can never fail the backup.
  describe "the reconciliation after a run" do
    setup context do
      assert {:ok, location} = Backup.save_destination(context.backup_directory)
      handler = "integrity-" <> Integer.to_string(System.unique_integer([:positive]))

      :ok =
        :telemetry.attach(
          handler,
          [:bnest_app, :backup, :integrity],
          &__MODULE__.forward_integrity/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler) end)
      %{location: location}
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: The report and the log line carry no private value
    test "reports the date and state of a run whose artifact was removed, once and privately",
         context do
      first = run_backup!(context.location, 1)
      File.rm!(artifact_path(context, first))
      File.rm!(Receipt.path(artifact_path(context, first)))
      drain_events()

      {second, log} = with_log(fn -> run_backup!(context.location, 0) end)

      assert_received {:integrity, %{problem_count: 1}, metadata}
      refute_received {:integrity, _measurements, _metadata}

      assert metadata == %{
               summary: "1 of 2 retained backups needs attention",
               problems: ["2026-08-30: file missing"],
               exit_status: 1
             }

      assert [_entry] = Regex.scan(~r/\[error\]/, log)
      assert log =~ "2026-08-30: file missing"
      assert_no_private_value(inspect(metadata) <> log, context, [first, second])
    end

    test "reports every retained backup present, without an error", context do
      first = run_backup!(context.location, 1)
      drain_events()

      {second, log} = with_log(fn -> run_backup!(context.location, 0) end)

      assert_received {:integrity, %{problem_count: 0}, metadata}
      refute_received {:integrity, _measurements, _metadata}

      assert metadata == %{
               summary: "all 2 retained backups are present",
               problems: [],
               exit_status: 0
             }

      refute log =~ "[error]"
      assert_no_private_value(inspect(metadata) <> log, context, [first, second])
    end

    # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
    # @scenario specs/apps/bnest/app-be/behaviours/scheduled_backups.feature: A reconciliation that raises leaves the backup verified
    test "a reconciliation that raises leaves the run verified and logs one path-free error",
         context do
      first = run_backup!(context.location, 1)
      # Without its receipt the first artifact is read by reconciliation alone: backup,
      # receipt writing and retention never look at it. It cannot be read, as by a disk error.
      File.rm!(Receipt.path(artifact_path(context, first)))
      :ok = UnreadableArtifactStore.install!(artifact_path(context, first))
      drain_events()

      {second, log} = with_log(fn -> run_backup!(context.location, 0) end)

      assert Enum.any?(
               Scheduler.verified_runs("prod_sqlite_backup"),
               &(&1.run_id == second.claim.run_id)
             )

      assert File.regular?(artifact_path(context, second))
      assert File.regular?(Receipt.path(artifact_path(context, second)))

      assert [_entry] = Regex.scan(~r/\[error\]/, log)

      assert log =~
               "Backup files: could not be checked. Run mix bnest.backup.reconcile on the host."

      refute log =~ "cannot be read"

      assert_received {:integrity, %{problem_count: 0}, metadata}
      refute_received {:integrity, _measurements, _metadata}
      assert metadata.exit_status == 1
      assert metadata.summary =~ "could not be checked"

      assert_no_private_value(inspect(metadata) <> log, context, [first, second])
    end
  end

  # The SQLite snapshot's restore reads only the active room, so an archived room, which the
  # schema can represent, never turns a restore into a failure. The room is the archived
  # second room the reply scenarios use, soft-deleted from the start; `INSERT OR IGNORE`
  # with its fixed ID keeps the run's shared Family Chat database idempotent.
  test "restores the active room of a real snapshot even when an archived room exists",
       context do
    FamilyChat.ensure_ready!()
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    SqliteRepo.query!(
      """
      INSERT OR IGNORE INTO family_chat_rooms (
        id, slug, name, room_kind, member_posting_enabled,
        created_at, created_by, updated_at, updated_by, deleted_at, deleted_by
      ) VALUES (900, 'ruang-arsip', 'Ruang Arsip', 'conversation', 1, ?, 'test', ?, 'test', ?, 'test')
      """,
      [now, now, now]
    )

    {:ok, location} = Backup.save_destination(context.backup_directory)

    {:ok, artifact} =
      Backup.run(deadline: @now, destination_directory: location.directory)

    assert {:ok, %{evidence: evidence}} = Backup.restore(artifact)
    assert %{"room" => room} = Jason.decode!(evidence)
    assert room["slug"] == FamilyChat.canonical_room_slug()
    refute room["slug"] == "ruang-arsip"
  end

  # While the snapshot copies the live database, members keep reading and sending: the
  # backup still completes, and the artifact restores into a self-consistent snapshot
  # whose ordered message IDs are exactly messages members sent, earliest first.
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A backup taken while the chat is busy restores as a consistent snapshot
  test "a backup taken while the chat is busy restores as a consistent snapshot",
       context do
    FamilyChat.ensure_ready!()
    {:ok, location} = Backup.save_destination(context.backup_directory)
    slug = FamilyChat.canonical_room_slug()

    before_ids =
      for n <- 1..3 do
        {:ok, message} =
          FamilyChat.send_message(
            "test-user-busy-quiet",
            slug,
            Ecto.UUID.generate(),
            "quiet #{n}"
          )

        message.id
      end

    # The snapshot holds the database's write lock while it copies, so a read or send
    # that lands mid-copy is refused busy; a member's client retries those, and the test
    # does the same, because the scenario only constrains the snapshot, not the probes.
    # Only the transient lock refusal is retried: any other error raises immediately.
    with_busy_retries = fn fun ->
      Enum.reduce_while(1..100, nil, fn _, _ ->
        try do
          {:halt, fun.()}
        rescue
          e in [Exqlite.Error] ->
            if e.message =~ "busy" do
              Process.sleep(20)
              {:cont, nil}
            else
              reraise e, __STACKTRACE__
            end
        end
      end)
    end

    senders =
      for n <- 1..3 do
        Task.async(fn ->
          for m <- 1..4 do
            with_busy_retries.(fn ->
              {:ok, message} =
                FamilyChat.send_message(
                  "test-user-busy-#{n}",
                  slug,
                  Ecto.UUID.generate(),
                  "busy #{n}.#{m}"
                )

              message.id
            end)
          end
        end)
      end

    readers =
      for _ <- 1..2 do
        Task.async(fn ->
          for _ <- 1..20 do
            with_busy_retries.(fn ->
              {:ok, _page} = FamilyChat.list_messages("test-user-busy-reader", slug, limit: 50)
            end)
          end
        end)
      end

    assert {:ok, artifact} =
             Backup.run(deadline: @now, destination_directory: location.directory)

    sent_ids = MapSet.new(before_ids ++ Enum.flat_map(senders, &Task.await(&1, 30_000)))
    Enum.each(readers, &Task.await(&1, 30_000))

    assert {:ok, %{evidence: evidence}} = Backup.restore(artifact)
    %{"orderedMessageIds" => restored_ids} = Jason.decode!(evidence)

    assert MapSet.subset?(MapSet.new(before_ids), MapSet.new(restored_ids))
    assert MapSet.subset?(MapSet.new(restored_ids), sent_ids)
    assert restored_ids == Enum.sort(restored_ids)
  end

  # Reads and sends keep working for the whole backup: two probes read and send in a loop
  # that only stops once the backup has finished, so every sample falls inside the backup
  # window. No probe fails, slow outliers stay within the scenario's budgets, and every
  # sent message is in the room history after.
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: Chat reads and sends stay within budget during a backup
  test "chat reads and sends stay within budget during a backup", context do
    FamilyChat.ensure_ready!()
    {:ok, location} = Backup.save_destination(context.backup_directory)
    slug = FamilyChat.canonical_room_slug()

    for n <- 1..500 do
      {:ok, _} =
        FamilyChat.send_message(
          "test-user-budget-seed",
          slug,
          Ecto.UUID.generate(),
          "seed #{n} " <> String.duplicate("x", 200)
        )
    end

    {:ok, flag} = Agent.start_link(fn -> false end)

    # The snapshot briefly refuses lock losers while it copies; a probe retries those
    # inside its own timing, so a transient refusal still completes without failure.
    with_busy_retries = fn fun ->
      Enum.reduce_while(1..100, nil, fn _, _ ->
        try do
          {:halt, fun.()}
        rescue
          e in [Exqlite.Error] ->
            if e.message =~ "busy" do
              Process.sleep(20)
              {:cont, nil}
            else
              reraise e, __STACKTRACE__
            end
        end
      end)
    end

    probe = fn user ->
      Stream.repeatedly(fn ->
        {read_ms, _} =
          with_busy_retries.(fn ->
            read_start = System.monotonic_time(:millisecond)
            {:ok, _page} = FamilyChat.list_messages(user, slug, limit: 50)
            {System.monotonic_time(:millisecond) - read_start, :ok}
          end)

        {send_ms, message_id} =
          with_busy_retries.(fn ->
            send_start = System.monotonic_time(:millisecond)

            {:ok, message} =
              FamilyChat.send_message(user, slug, Ecto.UUID.generate(), "budget probe")

            {System.monotonic_time(:millisecond) - send_start, message.id}
          end)

        {message_id, [read_ms, send_ms]}
      end)
      |> Enum.reduce_while([], fn sample, acc ->
        if acc != [] and Agent.get(flag, & &1), do: {:halt, acc}, else: {:cont, [sample | acc]}
      end)
    end

    probers = for n <- 1..2, do: Task.async(fn -> probe.("test-user-budget-#{n}") end)

    assert {:ok, _artifact} =
             Backup.run(deadline: @now, destination_directory: location.directory)

    Agent.update(flag, fn _ -> true end)
    completed = Enum.flat_map(probers, &Task.await(&1, 30_000))
    {sent_ids, samples} = Enum.unzip(completed)
    durations = List.flatten(samples)

    assert durations != []
    assert Enum.all?(durations, &(&1 <= 2_000))

    sorted = Enum.sort(durations)
    p95 = Enum.at(sorted, max(trunc(Float.ceil(length(sorted) * 0.95)) - 1, 0))
    assert p95 <= 500

    assert {:ok, %{nodes: nodes}} =
             FamilyChat.list_messages("test-user-budget-reader", slug, limit: 50)

    history_ids = MapSet.new(nodes, & &1.id)
    assert MapSet.subset?(MapSet.new(sent_ids), history_ids)
  end

  # A copy cut short by 100 bytes, less than one page, still opens and still reads its room,
  # messages and deliveries, so only the integrity proof tells it from an intact copy. The
  # restore must refuse it and remove the root it created.
  test "refuses a real snapshot cut short of its last bytes and leaves no restore root",
       context do
    FamilyChat.ensure_ready!()
    {:ok, location} = Backup.save_destination(context.backup_directory)
    {:ok, artifact} = Backup.run(deadline: @now, destination_directory: location.directory)
    assert {:ok, _restored} = Backup.restore(artifact)

    intact = File.read!(artifact.path)
    cut = binary_part(intact, 0, byte_size(intact) - 100)
    %{rows: [[page_size]]} = SqliteRepo.query!("PRAGMA page_size")

    # The cut is a sub-page one: the snapshot is whole pages and the copy is not.
    assert rem(byte_size(intact), page_size) == 0
    assert rem(byte_size(cut), page_size) != 0
    assert byte_size(intact) - byte_size(cut) < page_size

    truncated = %{artifact | path: Path.join(context.runtime.path, "cut-" <> artifact.basename)}
    File.write!(truncated.path, cut)
    roots = Backup.restore_roots()

    assert Backup.restore(truncated) == {:error, :restore_failed}
    assert Backup.restore_roots() == roots
  end

  # A copy whose last page is free, cut short by 100 bytes. SQLite zero-fills the missing tail of
  # the page, which nothing reads, so `PRAGMA quick_check` still returns ok and the copy reads
  # whole. Only its size, which is not its page count times its page size, tells it apart.
  test "refuses a cut copy that passes quick_check because its last page is free", context do
    FamilyChat.ensure_ready!()
    {:ok, location} = Backup.save_destination(context.backup_directory)
    {:ok, artifact} = Backup.run(deadline: @now, destination_directory: location.directory)
    assert {:ok, _restored} = Backup.restore(artifact)

    # Written past the snapshot's last page, then dropped, so the freed pages end the file.
    copy = Path.join(context.runtime.path, "free-tail-" <> artifact.basename)
    File.cp!(artifact.path, copy)
    {:ok, connection} = Exqlite.Sqlite3.open(copy)

    for sql <- [
          "CREATE TABLE scratch_pages (id INTEGER PRIMARY KEY, body TEXT)",
          "WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM c WHERE i < 60) " <>
            "INSERT INTO scratch_pages SELECT i, printf('%0*d', 3500, i) FROM c",
          "DROP TABLE scratch_pages"
        ] do
      :ok = Exqlite.Sqlite3.execute(connection, sql)
    end

    :ok = Exqlite.Sqlite3.close(connection)
    intact_size = File.stat!(copy).size
    File.write!(copy, binary_part(File.read!(copy), 0, intact_size - 100))

    # The cut is the case the size check exists for: the copy passes quick_check, yet its size
    # is not its page count times its page size.
    assert sqlite_rows(copy, "PRAGMA quick_check") == [["ok"]]
    assert [[page_count]] = sqlite_rows(copy, "PRAGMA page_count")
    assert [[page_size]] = sqlite_rows(copy, "PRAGMA page_size")
    assert File.stat!(copy).size == intact_size - 100
    refute File.stat!(copy).size == page_count * page_size

    roots = Backup.restore_roots()

    assert Backup.restore(%{path: copy}) == {:error, :restore_failed}
    assert Backup.restore_roots() == roots
  end

  defp sqlite_rows(path, sql) do
    {:ok, connection} = Exqlite.Sqlite3.open(path, mode: :readonly)

    try do
      {:ok, statement} = Exqlite.Sqlite3.prepare(connection, sql)
      {:ok, rows} = Exqlite.Sqlite3.fetch_all(connection, statement)
      rows
    after
      :ok = Exqlite.Sqlite3.close(connection)
    end
  end

  @doc false
  def forward_integrity(_event, measurements, metadata, pid),
    do: send(pid, {:integrity, measurements, metadata})

  # One scheduled-equivalent backup, `days_ago` days before the suite's clock, as the Scheduler
  # would run it: claimed, executed by the task and recorded verified.
  defp run_backup!(location, days_ago) do
    at = DateTime.add(@now, -days_ago * 86_400)

    {:ok, claim} =
      Scheduler.claim_setup(
        "prod-sqlite-backup-daily",
        "#{location.destination_id}-#{days_ago}",
        at
      )

    assert {:ok, receipt} = ScheduledBackupTask.execute(claim, at)
    %{claim: claim, receipt: receipt, destination_id: location.destination_id}
  end

  defp artifact_path(context, run),
    do: Path.join(context.backup_directory, run.receipt["artifactBasename"])

  defp drain_events do
    receive do
      {:integrity, _measurements, _metadata} -> drain_events()
    after
      0 -> :ok
    end
  end

  # What a log entry or an event must never carry: the destination's path or identifier, a run
  # ID, an artifact name, a digest, or any absolute path.
  defp assert_no_private_value(text, context, runs) do
    private =
      [context.backup_directory | Enum.map(runs, & &1.destination_id)] ++
        Enum.flat_map(runs, &[&1.claim.run_id, &1.receipt["artifactBasename"]])

    refute Enum.any?(private, &String.contains?(text, &1))
    refute text =~ ~r/[0-9a-f]{64}/
    refute text =~ ~r{(?:^|[\s"'(=:])/[\w.~-]}
  end

  defp canonical_temporary_root do
    {resolved, 0} = System.cmd("realpath", [System.tmp_dir!()])
    String.trim(resolved)
  end
end
