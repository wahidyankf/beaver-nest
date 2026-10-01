defmodule BnestApp.Identity.InMemoryIdentityStoreTest do
  use BnestApp.Test.Contracts.IdentityStoreContract, async: true

  alias BnestApp.Test.InMemory.IdentityStore, as: InMemoryIdentityStore

  defp new_store(_context), do: InMemoryIdentityStore.start()

  test "refuses to stand in for the configured adapter over Storage's record store" do
    assert_raise ArgumentError, ~r/cannot wrap a record store; start\/0 a store/, fn ->
      InMemoryIdentityStore.new(InMemoryIdentityStore.start())
    end
  end
end
