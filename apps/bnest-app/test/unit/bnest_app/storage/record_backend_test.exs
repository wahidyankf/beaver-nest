defmodule BnestApp.Storage.RecordBackendTest do
  use ExUnit.Case, async: true

  alias BnestApp.Storage.Ports.RecordBackend
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend

  test "delegates every operation to the backend that the state names" do
    store = InMemoryRecordBackend.start()
    record = %{"revision" => 0, "value" => "synthetic"}

    assert {:ok, ^record} = RecordBackend.put_new(store, :chat, "unit-user", record)
    assert {:ok, ^record} = RecordBackend.replace(store, :chat, "unit-user", record)
    assert :ok = RecordBackend.remove_exact(store, :chat, "unit-user", record)
    assert {:error, :missing} = RecordBackend.read(store, :chat, "unit-user")

    assert {:ok, %{"revision" => 0}} =
             RecordBackend.write(store, :chat, "unit-user", nil, %{"value" => "synthetic"})

    {:ok, _account} = RecordBackend.put_new(store, :account, "unit-user", record)
    refute RecordBackend.identity_files_empty?(store)
  end
end
