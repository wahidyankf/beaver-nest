defmodule BnestApp.StorageTest do
  # Not async: the doubles replace the application-wide Storage configuration.
  use ExUnit.Case, async: false

  alias BnestApp.Storage
  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestApp.Test.InMemory.StoragePorts.{FlatSource, MigrationLedger}

  @flat_root "/in-memory/flat"
  @theme_path "users/user-test-storage/preferences/theme.json"
  @sqlite_config %{
    "schemaVersion" => 1,
    "databaseDirectory" => "/in-memory/sqlite",
    "databaseFilename" => "bnest.sqlite3",
    "phase" => "sqlite_primary",
    "migrationId" => "flat-files-v1-to-sqlite-v1",
    "databaseGeneration" => "generation-unit"
  }

  setup do
    previous = StoragePorts.install()
    on_exit(fn -> StoragePorts.restore(previous) end)
    :ok
  end

  describe "configuration" do
    test "names each port's adapter and the registered record kinds" do
      assert Storage.adapter(:lock) == StoragePorts.Lock
      assert Storage.record_kinds() != []
      assert Storage.validate_record(%{}) == {:error, :invalid_schema}
      assert Storage.now() =~ ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/
    end

    test "a missing record-kind list registers none" do
      Application.put_env(
        :bnest_app,
        Storage,
        Keyword.delete(Application.fetch_env!(:bnest_app, Storage), :record_kinds)
      )

      assert Storage.record_kinds() == []
    end
  end

  describe "the database lifecycle" do
    test "starts, stops, and hands out the SQLite backend" do
      assert Storage.ensure_started!() == :ok
      assert Storage.ensure_started!("/in-memory/other.sqlite3") == :ok
      assert Storage.stop() == :ok
      assert {InMemoryRecordBackend, %{backend: InMemoryRecordBackend}} = Storage.record_backend()

      assert StoragePorts.calls() == [
               :ensure_started,
               {:ensure_started, "/in-memory/other.sqlite3"},
               :stop,
               :ensure_started
             ]
    end
  end

  describe "the storage pointer" do
    test "falls back to the default location until a pointer exists" do
      assert Storage.phase() == :flat_primary
      assert Storage.database_generation() == nil
      assert Storage.database_path() == Storage.default_directory() <> "/bnest.sqlite3"
    end

    test "the default directory follows the storage profile" do
      profile = Application.get_env(:bnest_app, :storage_profile)
      on_exit(fn -> Application.put_env(:bnest_app, :storage_profile, profile) end)

      Application.put_env(:bnest_app, :storage_profile, {:test, "run-unit"})
      assert Storage.default_directory() =~ ~r{/bnest/data/test/runs/run-unit$}

      Application.delete_env(:bnest_app, :storage_profile)
      assert Storage.default_directory() =~ ~r{/bnest/data/prod$}
    end

    test "reads the location, phase and generation of a pointer" do
      StoragePorts.put(:config, @sqlite_config)

      assert Storage.phase() == :sqlite_primary
      assert Storage.database_generation() == "generation-unit"
      assert Storage.database_path() == "/in-memory/sqlite/bnest.sqlite3"
    end

    test "records a chosen directory once" do
      assert Storage.validate_directory("relative") == {:error, :not_absolute}
      assert Storage.persist_directory("relative") == {:error, :not_absolute}

      assert {:ok, %{"databaseDirectory" => "/srv/bnest-unit"}} =
               Storage.persist_directory("/srv/bnest-unit")

      assert Storage.persist_directory("/srv/bnest-other") == {:error, :immutable}
    end

    test "refuses to choose over an unreadable pointer" do
      StoragePorts.put(:config, :invalid)

      assert Storage.persist_directory("/srv/bnest-unit") == {:error, :invalid}
    end
  end

  describe "the storage lease" do
    test "runs the function under the shared or exclusive lease" do
      assert Storage.with_shared_lock(fn -> :shared end) == :shared
      assert Storage.with_exclusive_lock(fn -> :exclusive end) == :exclusive
      assert StoragePorts.calls() == [:shared_lock, :exclusive_lock]
    end
  end

  describe "a scratch copy of the database" do
    @source "/in-memory/sqlite/bnest.sqlite3"

    setup do
      StoragePorts.put(:config, @sqlite_config)
      :ok
    end

    # A fingerprint that answers the scripted values in order, one per copy it is asked of.
    defp scripted(values) do
      {:ok, script} = Agent.start_link(fn -> values end)
      fn -> Agent.get_and_update(script, fn [head | rest] -> {head, rest} end) end
    end

    defp copy_cycle(number) do
      [
        {:open_database_copy, @source},
        :ensure_started,
        :stop,
        {:close_database_copy, "/in-memory/copy-#{number}/bnest.sqlite3"}
      ]
    end

    test "reads the second of two copies that agree and closes both" do
      assert {:ok, :read} =
               Storage.with_database_copy(scripted([{3, :latest}, {3, :latest}]), fn ->
                 send(self(), {:calls_at_read, StoragePorts.calls()})
                 :read
               end)

      # The second copy is open and the database started on it when it is read; the first is
      # already closed.
      assert_received {:calls_at_read, at_read}
      assert at_read == copy_cycle(1) ++ [{:open_database_copy, @source}, :ensure_started]
      assert StoragePorts.calls() == copy_cycle(1) ++ copy_cycle(2)
    end

    test "tries again after two copies that disagree, then reads the pair that agrees" do
      assert {:ok, :read} =
               Storage.with_database_copy(scripted([1, 2, 3, 3]), fn -> :read end)

      assert StoragePorts.calls() ==
               Enum.flat_map(1..4, &copy_cycle/1)
    end

    test "is unstable after two attempts whose copies disagree, and reads nothing" do
      assert Storage.with_database_copy(scripted([1, 2, 3, 4]), fn ->
               flunk("a ledger that kept changing must not be read")
             end) == {:error, :unstable}

      assert StoragePorts.calls() == Enum.flat_map(1..4, &copy_cycle/1)
    end

    test "cannot copy a database it cannot read, and starts nothing" do
      StoragePorts.put(:copy_failure?, true)

      assert Storage.with_database_copy(scripted([]), fn -> flunk("no copy to read") end) ==
               {:error, :copy_failed}

      assert StoragePorts.calls() == [{:open_database_copy, @source}]
    end

    test "closes the copy and passes on a failure of the fingerprint" do
      assert_raise RuntimeError, "unreadable ledger", fn ->
        Storage.with_database_copy(fn -> raise "unreadable ledger" end, fn -> :unreached end)
      end

      assert StoragePorts.calls() == copy_cycle(1)
    end

    test "closes the copy and passes on a failure of the read" do
      assert_raise RuntimeError, "unreadable read", fn ->
        Storage.with_database_copy(scripted([1, 1]), fn -> raise "unreadable read" end)
      end

      assert StoragePorts.calls() == copy_cycle(1) ++ copy_cycle(2)
    end
  end

  describe "the record store" do
    setup do
      flat = InMemoryRecordBackend.start()
      start_supervised!({Records, store: flat})
      %{flat: flat}
    end

    test "uses the flat store until SQLite is primary", %{flat: flat} do
      assert Storage.active_store() == flat
      assert Records.active_backend(flat) == {InMemoryRecordBackend, flat}
      assert Records.read(:theme, "user-test-storage") == {:error, :missing}

      StoragePorts.put(:config, @sqlite_config)

      assert Storage.active_store() == Records
      assert {InMemoryRecordBackend, sqlite} = Records.active_backend(flat)
      assert sqlite != flat
    end

    test "imports browser sources into the flat store", %{flat: flat} do
      source = %{
        "storageArea" => "localStorage",
        "storageKey" => "phx:theme",
        "payload" => "dark"
      }

      assert {:ok, %{record: %{"theme" => "dark"}}} =
               Storage.import_browser("user-test-storage", source)

      assert {:ok, %{"theme" => "dark"}} =
               InMemoryRecordBackend.read(flat, :theme, "user-test-storage")

      assert {:ok, %{record: nil}} = Storage.import_absent_theme("user-test-other")
    end
  end

  describe "the managed migration" do
    setup do
      FlatSource.put_files(@flat_root, [{@theme_path, theme_source("light")}])
      :ok
    end

    test "a dry run migrates without activating" do
      assert {:ok, :dry_run, %{run: %{accepted: 1, blocked: 0}, verification: nil}} =
               Storage.migrate(@flat_root, false)

      assert [:exclusive_lock, {:write_config, _config}, {:ensure_started, path} | rest] =
               StoragePorts.calls()

      assert path == Storage.default_directory() <> "/bnest.sqlite3"
      assert rest == [:migrate_schema]
      assert Storage.phase() == :flat_primary
    end

    test "activates a clean, verified run" do
      assert {:ok, :activated, %{verification: %{parity: true, integrity: true, restore: true}}} =
               Storage.migrate(@flat_root, true)

      assert Storage.phase() == :sqlite_primary
      assert [%{state: "verified"}] = MigrationLedger.state().runs
    end

    test "stops at a blocked run" do
      FlatSource.put_files(@flat_root, [{@theme_path, "{malformed"}])

      assert {:error, :blocked, %{run: %{blocked: 1}}} = Storage.migrate(@flat_root, true)

      FlatSource.put_files(@flat_root, [])
      assert {:error, :blocked, %{run: %{blocked: 0}}} = Storage.migrate(@flat_root, true)
      assert Storage.phase() == :flat_primary
    end

    test "does not activate a run that fails verification" do
      StoragePorts.put(:restore?, false)

      assert {:error, :verification_failed, %{verification: %{restore: false}}} =
               Storage.migrate(@flat_root, true)

      assert Storage.phase() == :flat_primary
    end
  end

  describe "the browser migration" do
    setup do
      FlatSource.put_files(@flat_root, [{@theme_path, theme_source("light")}])
      :ok
    end

    test "activates a clean run that passes integrity and parity" do
      assert %{blocked: 0} = Storage.move_data(@flat_root)
      assert Storage.phase() == :sqlite_primary
    end

    test "leaves a blocked or unverified run inactive" do
      StoragePorts.put(:integrity?, false)
      Storage.move_data(@flat_root)
      assert Storage.phase() == :flat_primary

      StoragePorts.put(:integrity?, true)
      FlatSource.put_files(@flat_root, [{@theme_path, "{malformed"}])

      assert %{blocked: 1} = Storage.move_data(@flat_root)
      assert Storage.phase() == :flat_primary
    end
  end

  describe "maintenance" do
    test "delegates each procedure to the maintenance adapter" do
      refute Storage.migration_started?()
      assert Storage.relocate("/srv/bnest-unit") == {:error, :absent}
      assert Storage.retire(@flat_root, "generation-unit", true) == {:ok, 0}
      assert Storage.purge_test_data("generation-unit", false) == {:ok, %{}}
      assert Storage.audit_schema(@flat_root) == {:ok, []}

      assert StoragePorts.calls() == [
               :migration_started?,
               {:relocate, "/srv/bnest-unit"},
               {:retire, @flat_root, "generation-unit", true},
               {:purge_test_data, "generation-unit", false},
               {:audit_schema, @flat_root}
             ]
    end
  end

  defp theme_source(theme),
    do:
      Jason.encode!(%{
        "schemaVersion" => 1,
        "recordType" => "theme-preference",
        "ownerId" => "user-test-storage",
        "sourceImportId" => nil,
        "revision" => 1,
        "theme" => theme,
        "updatedAt" => "2026-09-01T00:00:00Z"
      })
end
