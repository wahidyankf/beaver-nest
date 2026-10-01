defmodule BnestApp.Identity.RecordIdentityStoreTest do
  use BnestApp.Test.Contracts.IdentityStoreContract, async: true

  alias BnestApp.Identity.Adapters.RecordIdentityStore
  alias BnestApp.Storage.Adapters.FileRecordBackend
  alias BnestApp.TestRuntimeRoot

  # Over the flat-file record backend, which validates every record against its schema and
  # can enumerate its identity records. The routed `Storage.Records` repository cannot, so
  # it never claims to be empty and is not a contract user.
  defp new_store(_context) do
    runtime = TestRuntimeRoot.create!("record-identity-store")
    on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)
    RecordIdentityStore.new(FileRecordBackend.new!(runtime.path))
  end
end
