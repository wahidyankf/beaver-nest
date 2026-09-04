defmodule BnestApp.DataRepository.BackendTest do
  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.MemoryBackend
  alias BnestApp.DataRepository.Backend

  test "delegates exact removal to an injected backend" do
    store = MemoryBackend.start()
    record = %{"revision" => 0, "value" => "synthetic"}

    assert {:ok, ^record} = Backend.put_new(store, :chat, "unit-user", record)
    assert :ok = Backend.remove_exact(store, :chat, "unit-user", record)
    assert {:error, :missing} = Backend.read(store, :chat, "unit-user")
  end

  test "uses the production store when no backend is injected" do
    assert {:error, :unsupported_record_type} = Backend.read(%{}, :unsupported, "unit-user")
  end
end
