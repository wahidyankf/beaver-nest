defmodule BnestApp.Storage.RecoverySourceTest do
  use ExUnit.Case, async: true

  alias BnestApp.Storage.Ports.RecordBackend
  alias BnestApp.Storage.RecoverySource
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend

  @owner "user-test-recovery"
  @import_id "import-recovery"

  test "normalizes a preserved browser import again" do
    store = InMemoryRecordBackend.start()

    {:ok, _envelope} =
      RecordBackend.put_new(store, :browser_import, {@owner, @import_id}, envelope("dark"))

    assert {:ok, :theme, %{"theme" => "dark", "sourceImportId" => @import_id}} =
             RecoverySource.normalize_browser(store, @owner, @import_id)
  end

  test "refuses a missing or altered envelope" do
    store = InMemoryRecordBackend.start()

    assert RecoverySource.normalize_browser(store, @owner, @import_id) == {:error, :missing}

    altered = %{envelope("dark") | "payload" => "light"}

    {:ok, _envelope} =
      RecordBackend.put_new(store, :browser_import, {@owner, @import_id}, altered)

    assert RecoverySource.normalize_browser(store, @owner, @import_id) ==
             {:error, :checksum_mismatch}

    assert RecoverySource.verify_envelope(%{"payload" => "dark"}) == {:error, :invalid_schema}
  end

  defp envelope(payload) do
    %{
      "source" => %{"storageArea" => "localStorage", "storageKey" => "phx:theme"},
      "payload" => payload,
      "integrity" => %{"sha256" => :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)}
    }
  end
end
