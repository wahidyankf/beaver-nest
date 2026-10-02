defmodule BnestApp.Scheduler.DependencyTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Dependency-direction proof for Phase 5's REFACTOR item (delivery.md): the
  Scheduler orchestrator (`BnestApp.Scheduler`, `BnestApp.Scheduler.Run` and
  `BnestApp.Scheduler.TaskRegistry`) must reach every unit of scheduled work
  only through the dynamic `handler.execute/2` dispatch of the task the
  configuration registers -- never a hardcoded call to a concrete handler
  module or another context -- and must never issue SQL of its own outside
  its `Ports.ScheduleStore` adapter (`family_chat_operations.feature`'s "The
  Scheduler claims ... work only through the registered ... handler"). Each
  registered handler (Backup's `ScheduledBackupTask` adapter, Push Notifications'
  `RetentionTask` adapter) declares the `BnestApp.Scheduler.Ports.Task`
  behaviour and must in turn own only Scheduler claim/lease bookkeeping and
  delegate every domain SQL mechanic to its own public service module, never
  issuing SQL directly (the same Gherkin rule's "the handler delegates to the
  public ... service without direct SQL").

  The configuration (`config :bnest_app, BnestApp.Scheduler, tasks: ...,
  tick_handlers: ...`) is the one place a handler module name is *supposed*
  to appear (the registration table), the same way `BnestAppWeb.Schema`'s
  resolver-registration boundary allows what its own callers may not.

  Scans real source text, mirroring `BnestAppWeb.SchemaTest`'s identical
  technique for Phase 3's GraphQL boundary, so a handler that happens to
  produce a correct response by reaching around its service is still
  caught. File listing/reading is delegated to `BnestApp.SchemaSourceScan`
  (`test/support/`) so this unit-layer test file itself does not trip
  `test/behaviour/verify.exs`'s blanket filesystem-access scan.
  """

  alias BnestApp.SchemaSourceScan

  @orchestrator_files SchemaSourceScan.wildcard(["bnest_app", "scheduler.ex"]) ++
                        SchemaSourceScan.wildcard(["bnest_app", "scheduler", "run.ex"]) ++
                        SchemaSourceScan.wildcard(["bnest_app", "scheduler", "task_registry.ex"])

  @handler_files SchemaSourceScan.wildcard([
                   "bnest_app",
                   "backup",
                   "adapters",
                   "scheduled_backup_task.ex"
                 ]) ++
                   SchemaSourceScan.wildcard([
                     "bnest_app",
                     "push_notifications",
                     "adapters",
                     "retention_task.ex"
                   ])

  @sql_bypass [
    {~r/\bEcto\./, "direct Ecto access (bypasses the store port/service boundary)"},
    {~r/\bSqliteRepo\b/, "direct repo access (bypasses the store port/service boundary)"},
    {~r/"\s*SELECT\s|"\s*INSERT\s|"\s*UPDATE\s|"\s*DELETE\s/i, "inline SQL"}
  ]

  @hardcoded_handlers [
    {~r/\bBackup\b/,
     "hardcoded reference to Backup or its ScheduledBackupTask handler (must dispatch through the configured tasks only)"},
    {~r/\bRetentionTask\b/,
     "hardcoded reference to the Push Notifications RetentionTask handler (must dispatch through the configured tasks only)"},
    {~r/\bPushNotifications\b/,
     "hardcoded reference to Push Notifications (its tick handler must come from configuration)"}
  ]

  test "orchestrator and handler files exist to scan (this test cannot silently pass on an empty set)" do
    assert @orchestrator_files != [],
           "no Scheduler orchestrator files found under lib/bnest_app/scheduler*"

    assert length(@orchestrator_files) == 3,
           "expected scheduler.ex, scheduler/run.ex and scheduler/task_registry.ex, found: " <>
             inspect(@orchestrator_files)

    assert length(@handler_files) == 2,
           "expected both registered handler files (backup/adapters/scheduled_backup_task.ex and " <>
             "push_notifications/adapters/retention_task.ex), found: #{inspect(@handler_files)}"
  end

  test "the Scheduler orchestrator never issues SQL directly, only through its store port" do
    violations = scan(@orchestrator_files, @sql_bypass)

    assert violations == [],
           "Scheduler orchestrator dependency-direction violations:\n" <>
             Enum.join(violations, "\n")
  end

  test "the Scheduler orchestrator never hardcodes a handler or another context, only configured dispatch" do
    violations = scan(@orchestrator_files, @hardcoded_handlers)

    assert violations == [],
           "Scheduler orchestrator handler-dispatch violations:\n" <> Enum.join(violations, "\n")
  end

  test "registered handlers never issue SQL directly, only through their own public service module" do
    violations = scan(@handler_files, @sql_bypass)

    assert violations == [],
           "handler dependency-direction violations:\n" <> Enum.join(violations, "\n")
  end

  test "every configured task declares the Scheduler task behaviour, as each handler file does" do
    tasks = Application.fetch_env!(:bnest_app, BnestApp.Scheduler) |> Keyword.fetch!(:tasks)
    handlers = tasks |> Map.values() |> Enum.map(& &1.handler) |> Enum.uniq()

    assert handlers != []

    for handler <- handlers do
      behaviours = handler.module_info(:attributes) |> Keyword.get_values(:behaviour)
      assert BnestApp.Scheduler.Ports.Task in List.flatten(behaviours), inspect(handler)
    end

    for file <- @handler_files do
      assert SchemaSourceScan.read!(file) =~ "@behaviour BnestApp.Scheduler.Ports.Task",
             SchemaSourceScan.relative_to_cwd(file)
    end
  end

  defp scan(files, forbidden) do
    for file <- files,
        contents = SchemaSourceScan.read!(file),
        {pattern, reason} <- forbidden,
        Regex.match?(pattern, contents) do
      "#{SchemaSourceScan.relative_to_cwd(file)}: #{reason}"
    end
  end
end
