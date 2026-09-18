defmodule BnestApp.Scheduler.DependencyTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Dependency-direction proof for Phase 5's REFACTOR item (delivery.md): the
  Scheduler orchestrator (`BnestApp.Scheduler` / `BnestApp.Scheduler.Run`)
  must reach every unit of scheduled work only through
  `BnestApp.Scheduler.Registry`'s dynamic `handler.execute/2` dispatch --
  never a hardcoded call to a concrete handler module -- and must never
  issue SQL of its own outside `BnestApp.Scheduler.Store`
  (`family_chat_operations.feature`'s "The Scheduler claims ... work only
  through the registered ... handler"). Each registered handler
  (`BnestApp.Backup.Run`, `BnestApp.PushNotifications.RetentionJob`) must in
  turn own only Scheduler claim/lease bookkeeping and delegate every domain
  SQL mechanic to its own public service module, never issuing SQL directly
  (the same Gherkin rule's "the handler delegates to the public ... service
  without direct SQL").

  `BnestApp.Scheduler.Registry` itself is deliberately excluded from the
  scanned orchestrator files: it is the one place a handler module name is
  *supposed* to appear (the registration table), the same way
  `BnestAppWeb.Schema`'s resolver-registration boundary allows what its own
  callers may not.

  Scans real source text, mirroring `BnestAppWeb.SchemaTest`'s identical
  technique for Phase 3's GraphQL boundary, so a handler that happens to
  produce a correct response by reaching around its service is still
  caught. File listing/reading is delegated to `BnestApp.SchemaSourceScan`
  (`test/support/`) so this unit-layer test file itself does not trip
  `test/behaviour/verify.exs`'s blanket filesystem-access scan.
  """

  alias BnestApp.SchemaSourceScan

  @orchestrator_files SchemaSourceScan.wildcard(["bnest_app", "scheduler.ex"]) ++
                        SchemaSourceScan.wildcard(["bnest_app", "scheduler", "run.ex"])

  @handler_files SchemaSourceScan.wildcard(["bnest_app", "backup", "run.ex"]) ++
                   SchemaSourceScan.wildcard([
                     "bnest_app",
                     "push_notifications",
                     "retention_job.ex"
                   ])

  @sql_bypass [
    {~r/\bEcto\./, "direct Ecto access (bypasses the Store/service boundary)"},
    {~r/\bSqliteRepo\b/, "direct repo access (bypasses the Store/service boundary)"},
    {~r/"\s*SELECT\s|"\s*INSERT\s|"\s*UPDATE\s|"\s*DELETE\s/i, "inline SQL"}
  ]

  @hardcoded_handlers [
    {~r/\bBackup\.Run\b/,
     "hardcoded reference to the Backup.Run handler (must dispatch through Scheduler.Registry only)"},
    {~r/\bPushNotifications\.RetentionJob\b/,
     "hardcoded reference to the PushNotifications.RetentionJob handler (must dispatch through Scheduler.Registry only)"}
  ]

  test "orchestrator and handler files exist to scan (this test cannot silently pass on an empty set)" do
    assert @orchestrator_files != [],
           "no Scheduler orchestrator files found under lib/bnest_app/scheduler*"

    assert @handler_files != [],
           "no registered handler files found under lib/bnest_app/backup or push_notifications"
  end

  test "the Scheduler orchestrator never issues SQL directly, only through Scheduler.Store" do
    violations = scan(@orchestrator_files, @sql_bypass)

    assert violations == [],
           "Scheduler orchestrator dependency-direction violations:\n" <>
             Enum.join(violations, "\n")
  end

  test "the Scheduler orchestrator never hardcodes a concrete handler module, only Registry dispatch" do
    violations = scan(@orchestrator_files, @hardcoded_handlers)

    assert violations == [],
           "Scheduler orchestrator handler-dispatch violations:\n" <> Enum.join(violations, "\n")
  end

  test "registered handlers never issue SQL directly, only through their own public service module" do
    violations = scan(@handler_files, @sql_bypass)

    assert violations == [],
           "handler dependency-direction violations:\n" <> Enum.join(violations, "\n")
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
