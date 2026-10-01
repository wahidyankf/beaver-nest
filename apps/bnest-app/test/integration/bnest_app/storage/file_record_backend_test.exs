defmodule BnestApp.Storage.FileRecordBackendTest do
  use BnestApp.Test.Contracts.RecordBackendContract, async: true

  alias BnestApp.Storage.Adapters.FileRecordBackend
  alias BnestApp.TestRuntimeRoot

  defp new_store(_context) do
    runtime = TestRuntimeRoot.create!("file-record-backend")
    on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)
    FileRecordBackend.new!(runtime.path)
  end
end
