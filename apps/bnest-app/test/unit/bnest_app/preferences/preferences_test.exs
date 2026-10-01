defmodule BnestApp.Preferences.PreferencesUnitTest do
  # Not async: the configured-store tests install the Storage port doubles, which are
  # application-wide configuration, and start the named record repository. Every other test
  # passes its own in-memory store handle.
  use ExUnit.Case, async: false

  alias BnestApp.Preferences
  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.PreferenceStore, as: InMemoryPreferenceStore
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.StoragePorts

  @owner "test-user-preferences-unit"
  @now ~U[2026-10-01 08:30:15.123456Z]

  # A store whose reads answer with a fixed result while writes and removals reach a real
  # in-memory store, so a test can stage a record that changed after the facade read it.
  defmodule StaleReadStore do
    @moduledoc false

    @behaviour BnestApp.Preferences.Ports.PreferenceStore

    alias BnestApp.Test.InMemory.PreferenceStore, as: InMemoryPreferenceStore

    def wrap(inner, read_result),
      do: %{adapter: __MODULE__, inner: inner, read_result: read_result}

    @impl true
    def new, do: raise(ArgumentError, "start a store and pass its handle")

    @impl true
    def read(store, _owner_id), do: store.read_result

    @impl true
    def write(store, owner_id, expected_revision, record),
      do: InMemoryPreferenceStore.write(store.inner, owner_id, expected_revision, record)

    @impl true
    def remove_exact(store, owner_id, expected),
      do: InMemoryPreferenceStore.remove_exact(store.inner, owner_id, expected)
  end

  setup do
    %{store: InMemoryPreferenceStore.start()}
  end

  describe "themes/0" do
    test "lists the system, light and dark themes" do
      assert Preferences.themes() == ["system", "light", "dark"]
    end
  end

  describe "theme/1" do
    test "is the system theme when the user stored no preference", %{store: store} do
      assert Preferences.theme(@owner, store: store) == "system"
    end

    test "is the stored theme once the user chose one", %{store: store} do
      :ok = Preferences.put_theme(@owner, "light", @now, store: store)

      assert Preferences.theme(@owner, store: store) == "light"
    end

    test "falls back to the system theme when the preference cannot be read", %{store: store} do
      unreadable = StaleReadStore.wrap(store, {:error, :invalid})

      assert Preferences.theme(@owner, store: unreadable) == "system"
    end
  end

  describe "put_theme/3" do
    test "stores a new theme-preference record in its unchanged format", %{store: store} do
      assert Preferences.put_theme(@owner, "dark", @now, store: store) == :ok

      assert InMemoryPreferenceStore.snapshot(store) == %{
               @owner => %{
                 "schemaVersion" => 1,
                 "recordType" => "theme-preference",
                 "ownerId" => @owner,
                 "sourceImportId" => nil,
                 "theme" => "dark",
                 "updatedAt" => "2026-10-01T08:30:15Z",
                 "revision" => 0
               }
             }
    end

    test "replaces an existing preference at its revision and keeps its import source",
         %{store: store} do
      {:ok, _imported} =
        InMemoryPreferenceStore.write(store, @owner, nil, %{
          "schemaVersion" => 1,
          "recordType" => "theme-preference",
          "ownerId" => @owner,
          "sourceImportId" => "test-import-1",
          "theme" => "dark",
          "updatedAt" => "2026-09-30T00:00:00Z"
        })

      assert Preferences.put_theme(@owner, "light", @now, store: store) == :ok

      assert {:ok,
              %{
                "theme" => "light",
                "sourceImportId" => "test-import-1",
                "updatedAt" => "2026-10-01T08:30:15Z",
                "revision" => 1
              }} = InMemoryPreferenceStore.read(store, @owner)
    end

    test "refuses to overwrite a preference that changed after it was read", %{store: store} do
      :ok = Preferences.put_theme(@owner, "dark", @now, store: store)
      {:ok, read_earlier} = InMemoryPreferenceStore.read(store, @owner)
      :ok = Preferences.put_theme(@owner, "light", @now, store: store)
      stale = StaleReadStore.wrap(store, {:ok, read_earlier})

      assert Preferences.put_theme(@owner, "dark", @now, store: stale) == {:error, :stale}

      assert {:ok, %{"theme" => "light", "revision" => 1}} =
               InMemoryPreferenceStore.read(store, @owner)
    end

    test "returns the read failure and writes nothing", %{store: store} do
      unreadable = StaleReadStore.wrap(store, {:error, :invalid})

      assert Preferences.put_theme(@owner, "dark", @now, store: unreadable) == {:error, :invalid}
      assert InMemoryPreferenceStore.snapshot(store) == %{}
    end

    test "choosing the system theme removes the stored preference", %{store: store} do
      :ok = Preferences.put_theme(@owner, "dark", @now, store: store)

      assert Preferences.put_theme(@owner, "system", @now, store: store) == :ok
      assert InMemoryPreferenceStore.snapshot(store) == %{}
    end

    test "rejects an unknown theme without touching the store", %{store: store} do
      :ok = Preferences.put_theme(@owner, "dark", @now, store: store)
      before = InMemoryPreferenceStore.snapshot(store)

      assert Preferences.put_theme(@owner, "sepia", @now, store: store) ==
               {:error, :invalid_theme}

      assert Preferences.put_theme(@owner, nil, @now, store: store) == {:error, :invalid_theme}
      assert InMemoryPreferenceStore.snapshot(store) == before
    end
  end

  describe "clear_theme/1" do
    test "removes the stored preference", %{store: store} do
      :ok = Preferences.put_theme(@owner, "dark", @now, store: store)

      assert Preferences.clear_theme(@owner, store: store) == :ok
      assert InMemoryPreferenceStore.read(store, @owner) == {:error, :missing}
      assert Preferences.theme(@owner, store: store) == "system"
    end

    test "is a no-op when no preference is stored", %{store: store} do
      assert Preferences.clear_theme(@owner, store: store) == :ok
      assert InMemoryPreferenceStore.snapshot(store) == %{}
    end

    test "keeps a preference that changed after it was read", %{store: store} do
      :ok = Preferences.put_theme(@owner, "dark", @now, store: store)
      {:ok, read_earlier} = InMemoryPreferenceStore.read(store, @owner)
      :ok = Preferences.put_theme(@owner, "light", @now, store: store)
      stale = StaleReadStore.wrap(store, {:ok, read_earlier})

      assert Preferences.clear_theme(@owner, store: stale) == {:error, :changed}
      assert {:ok, %{"theme" => "light"}} = InMemoryPreferenceStore.read(store, @owner)
    end

    test "returns the read failure and removes nothing", %{store: store} do
      :ok = Preferences.put_theme(@owner, "dark", @now, store: store)
      unreadable = StaleReadStore.wrap(store, {:error, :invalid})

      assert Preferences.clear_theme(@owner, store: unreadable) == {:error, :invalid}
      assert {:ok, %{"theme" => "dark"}} = InMemoryPreferenceStore.read(store, @owner)
    end
  end

  # Without `store:` the facade works on the configured preference store, which the unit
  # layer keeps record-backed: it reaches Storage's record repository, started here over an
  # in-memory record backend.
  describe "the configured store" do
    setup do
      previous = StoragePorts.install()
      on_exit(fn -> StoragePorts.restore(previous) end)
      records = InMemoryRecordBackend.start()
      start_supervised!({Records, store: records})
      %{records: records}
    end

    test "keeps the theme as the :theme record of its owner", %{records: records} do
      assert Preferences.put_theme(@owner, "dark", @now) == :ok

      assert InMemoryRecordBackend.snapshot(records) == %{
               {:theme, @owner} => %{
                 "schemaVersion" => 1,
                 "recordType" => "theme-preference",
                 "ownerId" => @owner,
                 "sourceImportId" => nil,
                 "theme" => "dark",
                 "updatedAt" => "2026-10-01T08:30:15Z",
                 "revision" => 0
               }
             }

      assert Preferences.theme(@owner) == "dark"
      assert Preferences.clear_theme(@owner) == :ok
      assert InMemoryRecordBackend.snapshot(records) == %{}
      assert Preferences.theme(@owner) == "system"
    end
  end
end
