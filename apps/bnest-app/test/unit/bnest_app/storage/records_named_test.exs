defmodule BnestApp.Storage.RecordsNamedTest do
  # Not async: it registers under the production process name.
  use ExUnit.Case, async: false

  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend

  defmodule PassthroughLock do
    @moduledoc false
    def with_shared(fun), do: fun.()
  end

  defmodule DirectCoordinator do
    @moduledoc false
    def active_backend(store), do: {InMemoryRecordBackend, store}
  end

  setup do
    store = InMemoryRecordBackend.start()

    start_supervised!(
      {Records, store: store, lock: PassthroughLock, coordinator: DirectCoordinator}
    )

    %{store: store}
  end

  test "the registered process serves every operation without an explicit server", %{
    store: store
  } do
    assert Records.store() == store

    assert {:ok, %{"balance" => 1}} = Records.put_new(:account, "u", %{"balance" => 1})
    assert Records.read(:account, "u") == {:ok, %{"balance" => 1}}
    assert {:ok, %{"revision" => 0}} = Records.write(:account, "w", nil, %{})
    assert {:ok, %{"balance" => 2}} = Records.replace(:account, "u", %{"balance" => 2})
    assert Records.remove_exact(:account, "u", %{"balance" => 2}) == :ok
    assert Records.read(:account, "u") == {:error, :missing}
  end
end
