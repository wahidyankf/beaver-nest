defmodule BnestApp.Storage.ScratchCopyTest do
  use ExUnit.Case, async: false

  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.ScratchCopy
  alias BnestApp.TestRuntimeRoot

  @pointer_variable "BNEST_STORAGE_CONFIG"
  @database_bytes "synthetic database bytes"
  @wal_bytes "synthetic write-ahead log bytes"

  # The copies go under a temporary directory of this test's own, and the source database is a
  # pair of synthetic files beside no `-shm`: the adapter copies bytes and opens nothing.
  setup do
    runtime = TestRuntimeRoot.create!("scratch-copy")
    source_directory = Path.join(runtime.sqlite_path, "source")
    temporary_root = Path.join(runtime.sqlite_path, "tmp")
    File.mkdir_p!(source_directory)
    File.mkdir_p!(temporary_root)

    previous_pointer = System.get_env(@pointer_variable)
    previous_temporary = System.get_env("TMPDIR")
    System.put_env("TMPDIR", temporary_root)

    on_exit(fn ->
      restore(@pointer_variable, previous_pointer)
      restore("TMPDIR", previous_temporary)
      TestRuntimeRoot.cleanup!(runtime)
    end)

    source = Path.join(source_directory, "bnest.sqlite3")
    File.write!(source, @database_bytes)
    File.write!(source <> "-wal", @wal_bytes)

    %{source: source, source_directory: source_directory, temporary_root: temporary_root}
  end

  test "copies the database and its log into a private directory, each under its own name",
       context do
    assert {:ok, copy} = ScratchCopy.open(context.source)

    directory = Path.dirname(copy.database_path)
    assert Path.dirname(directory) == context.temporary_root
    assert Path.basename(copy.database_path) == "bnest.sqlite3"
    assert File.read!(copy.database_path) == @database_bytes
    assert File.read!(copy.database_path <> "-wal") == @wal_bytes

    assert File.ls!(directory) |> Enum.sort() == [
             "bnest.sqlite3",
             "bnest.sqlite3-wal",
             "storage.json"
           ]

    assert mode(directory) == 0o700
    assert mode(copy.database_path) == 0o600
    assert mode(copy.database_path <> "-wal") == 0o600
  end

  test "leaves the source as it was and creates no sidecar beside it", context do
    assert {:ok, copy} = ScratchCopy.open(context.source)
    assert :ok = ScratchCopy.close(copy)

    assert File.read!(context.source) == @database_bytes
    assert File.read!(context.source <> "-wal") == @wal_bytes

    assert File.ls!(context.source_directory) |> Enum.sort() == [
             "bnest.sqlite3",
             "bnest.sqlite3-wal"
           ]
  end

  test "points storage at the copy until it is closed", context do
    System.put_env(@pointer_variable, Path.join(context.source_directory, "storage.json"))

    assert {:ok, copy} = ScratchCopy.open(context.source)
    assert Storage.database_path() == copy.database_path
    assert Storage.phase() == :sqlite_primary

    assert :ok = ScratchCopy.close(copy)

    assert System.get_env(@pointer_variable) ==
             Path.join(context.source_directory, "storage.json")
  end

  test "leaves no pointer variable behind when there was none", context do
    System.delete_env(@pointer_variable)

    assert {:ok, copy} = ScratchCopy.open(context.source)

    assert FileConfigStore.pointer_path() ==
             Path.join(Path.dirname(copy.database_path), "storage.json")

    assert :ok = ScratchCopy.close(copy)

    assert System.get_env(@pointer_variable) == nil
  end

  test "removes the copy, the log copy and the pointer when it is closed", context do
    assert {:ok, copy} = ScratchCopy.open(context.source)
    assert File.dir?(Path.dirname(copy.database_path))
    assert :ok = ScratchCopy.close(copy)

    assert File.ls!(context.temporary_root) == []
  end

  test "copies a database without a log, under whatever name it has", context do
    renamed = Path.join(context.source_directory, "ledger.sqlite3")
    File.rename!(context.source, renamed)
    File.rm!(context.source <> "-wal")

    assert {:ok, copy} = ScratchCopy.open(renamed)

    assert Path.basename(copy.database_path) == "ledger.sqlite3"
    assert File.read!(copy.database_path) == @database_bytes
    refute File.exists?(copy.database_path <> "-wal")
  end

  test "cannot copy a database that is not there, and leaves nothing behind", context do
    System.put_env(@pointer_variable, "/synthetic/test-user/storage.json")

    assert ScratchCopy.open(Path.join(context.source_directory, "absent.sqlite3")) ==
             {:error, :copy_failed}

    assert File.ls!(context.temporary_root) == []
    assert System.get_env(@pointer_variable) == "/synthetic/test-user/storage.json"
  end

  defp mode(path), do: Bitwise.band(File.stat!(path).mode, 0o777)

  defp restore(name, nil), do: System.delete_env(name)
  defp restore(name, value), do: System.put_env(name, value)
end
