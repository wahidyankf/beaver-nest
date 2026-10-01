defmodule BnestApp.SifatAllah.SifatAllahUnitTest do
  # Not async: the configured-store test installs the Storage port doubles, which are
  # application-wide configuration, and starts the named record repository. Every other test
  # passes its own in-memory store handle.
  use ExUnit.Case, async: false

  alias BnestApp.SifatAllah
  alias BnestApp.SifatAllah.Domain.Quiz
  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.ProgressStore, as: InMemoryProgressStore
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.StoragePorts

  @owner "test-user-sifat-allah-unit"
  @now ~U[2026-10-01 08:30:15.123456Z]
  @study %{"mode" => "study", "lesson_ids" => ["wujud"], "lesson_index" => 0, "feedback" => nil}

  setup do
    %{store: InMemoryProgressStore.start()}
  end

  describe "load_progress/1" do
    test "is missing when the learner saved no progress", %{store: store} do
      assert SifatAllah.load_progress(@owner, store: store) == {:error, :missing}
    end

    test "is the record the learner's last save stored", %{store: store} do
      {:ok, saved} = SifatAllah.save_progress(@owner, snapshot(), nil, store: store, now: @now)

      assert SifatAllah.load_progress(@owner, store: store) == {:ok, saved}
    end
  end

  describe "save_progress/3" do
    test "a first save stores a new sifat-allah-progress record in its unchanged format",
         %{store: store} do
      progress = Quiz.remember(Quiz.progress(), "wujud")

      assert {:ok, record} =
               SifatAllah.save_progress(@owner, Map.put(progress, "session", @study), nil,
                 store: store,
                 now: @now
               )

      expected = %{
        "schemaVersion" => 1,
        "recordType" => "sifat-allah-progress",
        "ownerId" => @owner,
        "sourceImportId" => nil,
        "progress" => progress,
        "session" => @study,
        "updatedAt" => "2026-10-01T08:30:15Z",
        "revision" => 0
      }

      assert record == expected
      assert InMemoryProgressStore.snapshot(store) == %{@owner => expected}
    end

    test "replaces the previous record at its revision and keeps its import source",
         %{store: store} do
      {:ok, imported} =
        InMemoryProgressStore.write(store, @owner, nil, %{
          "schemaVersion" => 1,
          "recordType" => "sifat-allah-progress",
          "ownerId" => @owner,
          "sourceImportId" => "test-import-1",
          "progress" => Quiz.progress(),
          "session" => %{"mode" => "dashboard"},
          "updatedAt" => "2026-09-30T00:00:00Z"
        })

      assert {:ok, record} =
               SifatAllah.save_progress(@owner, snapshot(@study), imported,
                 store: store,
                 now: @now
               )

      assert %{
               "sourceImportId" => "test-import-1",
               "session" => @study,
               "updatedAt" => "2026-10-01T08:30:15Z",
               "revision" => 1
             } = record

      assert InMemoryProgressStore.read(store, @owner) == {:ok, record}
    end

    test "refuses to overwrite progress that changed after it was read", %{store: store} do
      {:ok, read_earlier} =
        SifatAllah.save_progress(@owner, snapshot(), nil, store: store, now: @now)

      {:ok, current} =
        SifatAllah.save_progress(@owner, snapshot(@study), read_earlier, store: store, now: @now)

      assert SifatAllah.save_progress(@owner, snapshot(), read_earlier, store: store, now: @now) ==
               {:error, :stale}

      assert InMemoryProgressStore.read(store, @owner) == {:ok, current}
    end

    test "a first save keeps progress another session already stored", %{store: store} do
      {:ok, stored} = SifatAllah.save_progress(@owner, snapshot(), nil, store: store, now: @now)

      assert SifatAllah.save_progress(@owner, snapshot(@study), nil, store: store, now: @now) ==
               {:error, :stale}

      assert InMemoryProgressStore.read(store, @owner) == {:ok, stored}
    end
  end

  # Without `store:` the facade works on the configured progress store, which the unit layer
  # keeps record-backed: it reaches Storage's record repository, started here over an
  # in-memory record backend.
  describe "the configured store" do
    setup do
      previous = StoragePorts.install()
      on_exit(fn -> StoragePorts.restore(previous) end)
      records = InMemoryRecordBackend.start()
      start_supervised!({Records, store: records})
      %{records: records}
    end

    test "keeps the progress as the :sifat_allah record of its owner", %{records: records} do
      assert {:ok, saved} = SifatAllah.save_progress(@owner, snapshot(@study), nil, now: @now)

      assert InMemoryRecordBackend.snapshot(records) == %{
               {:sifat_allah, @owner} => %{
                 "schemaVersion" => 1,
                 "recordType" => "sifat-allah-progress",
                 "ownerId" => @owner,
                 "sourceImportId" => nil,
                 "progress" => Quiz.progress(),
                 "session" => @study,
                 "updatedAt" => "2026-10-01T08:30:15Z",
                 "revision" => 0
               }
             }

      assert SifatAllah.load_progress(@owner) == {:ok, saved}
      assert {:ok, %{"revision" => 1}} = SifatAllah.save_progress(@owner, snapshot(), saved)
      assert SifatAllah.save_progress(@owner, snapshot(), saved) == {:error, :stale}
    end
  end

  defp snapshot(session \\ %{"mode" => "dashboard"}),
    do: Map.put(Quiz.progress(), "session", session)
end
