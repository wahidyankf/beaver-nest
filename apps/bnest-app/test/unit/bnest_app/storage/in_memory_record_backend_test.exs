defmodule BnestApp.Storage.InMemoryRecordBackendTest do
  use BnestApp.Test.Contracts.RecordBackendContract, async: true

  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend

  defp new_store(_context), do: InMemoryRecordBackend.start()
end
