defmodule BnestApp.DataRepositoryNamedUnitTest do
  # Not async: it registers under the production process name.
  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.MemoryBackend
  alias BnestApp.DataRepository

  defmodule PassthroughLock do
    @moduledoc false
    def with_shared(fun), do: fun.()
  end

  defmodule DirectCoordinator do
    @moduledoc false
    def active_backend(store), do: {MemoryBackend, store}
  end

  setup do
    store = MemoryBackend.start()

    start_supervised!(
      {DataRepository, store: store, lock: PassthroughLock, coordinator: DirectCoordinator}
    )

    %{store: store}
  end

  test "the registered process serves every operation without an explicit server", %{
    store: store
  } do
    assert DataRepository.store() == store

    assert {:ok, %{"balance" => 1}} = DataRepository.put_new(:account, "u", %{"balance" => 1})
    assert DataRepository.read(:account, "u") == {:ok, %{"balance" => 1}}
    assert {:ok, %{"revision" => 0}} = DataRepository.write(:account, "w", nil, %{})
    assert {:ok, %{"balance" => 2}} = DataRepository.replace(:account, "u", %{"balance" => 2})
    assert DataRepository.remove_exact(:account, "u", %{"balance" => 2}) == :ok
    assert DataRepository.read(:account, "u") == {:error, :missing}
  end
end
