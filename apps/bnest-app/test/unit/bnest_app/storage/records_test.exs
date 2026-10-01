defmodule BnestApp.Storage.RecordsTest do
  use ExUnit.Case, async: true

  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend

  # Both doubles run in the caller's process, because Records resolves its context
  # and takes the lease there rather than inside the GenServer. That lets one mailbox record
  # the ordering the real lock depends on.
  defmodule LockSpy do
    @moduledoc false

    def with_shared(fun) do
      send(self(), :lease_acquired)
      result = fun.()
      send(self(), :lease_released)
      result
    end
  end

  defmodule CoordinatorSpy do
    @moduledoc false

    def active_backend(store) do
      send(self(), :backend_resolved)
      {InMemoryRecordBackend, store}
    end
  end

  setup do
    store = InMemoryRecordBackend.start()

    repository =
      start_supervised!(
        {Records, name: nil, store: store, lock: LockSpy, coordinator: CoordinatorSpy}
      )

    %{store: store, repository: repository}
  end

  @lease_events [:lease_acquired, :backend_resolved, :lease_released]

  # Drained as an ordered list rather than asserted with assert_received, which scans the
  # whole mailbox and would accept the events in any order.
  defp lease_events(acc \\ []) do
    receive do
      event when event in @lease_events -> lease_events([event | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp flush_lease_messages, do: lease_events()

  test "store/1 replies with the store it was given", %{
    repository: repository,
    store: store
  } do
    assert Records.store(repository) == store
  end

  test "put_new writes through the active backend", %{repository: repository, store: store} do
    assert {:ok, %{"name" => "ledger"}} =
             Records.put_new(:account, "user-1", %{"name" => "ledger"}, repository)

    assert InMemoryRecordBackend.read(store, :account, "user-1") == {:ok, %{"name" => "ledger"}}

    assert Records.put_new(:account, "user-1", %{"name" => "other"}, repository) ==
             {:error, :exists}
  end

  test "read returns a missing error for an absent record", %{repository: repository} do
    assert Records.read(:account, "absent", repository) == {:error, :missing}
  end

  test "write enforces the expected revision", %{repository: repository} do
    assert {:ok, %{"revision" => 0}} =
             Records.write(:account, "user-1", nil, %{"name" => "first"}, repository)

    assert {:ok, %{"revision" => 1}} =
             Records.write(:account, "user-1", 0, %{"name" => "second"}, repository)

    assert Records.write(:account, "user-1", 0, %{"name" => "stale"}, repository) ==
             {:error, :stale}
  end

  test "replace requires an existing record", %{repository: repository} do
    assert Records.replace(:account, "absent", %{"name" => "x"}, repository) ==
             {:error, :missing}

    {:ok, _created} = Records.put_new(:account, "user-1", %{"name" => "a"}, repository)

    assert {:ok, %{"name" => "b"}} =
             Records.replace(:account, "user-1", %{"name" => "b"}, repository)
  end

  test "remove_exact refuses to delete a record that changed", %{repository: repository} do
    {:ok, _created} = Records.put_new(:account, "user-1", %{"name" => "a"}, repository)

    assert Records.remove_exact(:account, "user-1", %{"name" => "changed"}, repository) ==
             {:error, :changed}

    assert Records.remove_exact(:account, "user-1", %{"name" => "a"}, repository) == :ok
    assert Records.read(:account, "user-1", repository) == {:error, :missing}
  end

  # The invariant that matters for authoritative family data: the backend is chosen and used
  # while the shared lease is held, so an exclusive holder cannot swap it mid-operation.
  # Hoisting the coordinator call out of the lease reorders these messages and fails here.
  for {label, call} <- [
        {"read", quote(do: Records.read(:account, "user-1", var!(repository)))},
        {"write", quote(do: Records.write(:account, "user-1", nil, %{}, var!(repository)))},
        {"put_new", quote(do: Records.put_new(:account, "user-2", %{}, var!(repository)))},
        {"replace", quote(do: Records.replace(:account, "user-1", %{}, var!(repository)))},
        {"remove_exact",
         quote(do: Records.remove_exact(:account, "user-1", %{}, var!(repository)))}
      ] do
    test "#{label} resolves the backend inside the shared lease", %{repository: repository} do
      var!(repository) = repository
      flush_lease_messages()

      _result = unquote(call)

      assert lease_events() == [:lease_acquired, :backend_resolved, :lease_released]
    end
  end
end
