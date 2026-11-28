defmodule BnestApp.Behaviour.HttpEndpoints.InvalidRolesStoreTest do
  @moduledoc """
  Unit tests for the integration adapter's invalid-roles identity store. The
  double reads every account through the real identity store and carries the
  row's roles instead of the stored ones, so the session user the endpoint
  observes has no usable role while the session itself stays real.
  """

  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.HttpEndpoints.IntegrationAdapter.InvalidRolesStore
  alias BnestApp.Identity
  alias BnestApp.Identity.Ports.IdentityStore
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend

  @account %{"userId" => "test-user-invalid-roles-owner", "roles" => ["admin"]}

  setup do
    backend = InMemoryRecordBackend.start()
    real = Identity.adapter(:identity_store)
    assert {:ok, _} = real.new(backend) |> IdentityStore.put_account(@account)

    Application.put_env(:bnest_app, InvalidRolesStore, real: real, roles: [])

    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:bnest_app, InvalidRolesStore) end)

    %{store: InvalidRolesStore.new(backend)}
  end

  test "carries the row's roles instead of the stored ones", %{store: store} do
    assert {:ok, %{"roles" => [], "userId" => "test-user-invalid-roles-owner"}} =
             IdentityStore.read_account(store, @account["userId"])
  end

  test "delegates every other read to the real store", %{store: store} do
    assert {:error, :missing} = IdentityStore.read_session(store, "digest-test-user")
    assert {:error, :missing} = IdentityStore.read_bootstrap(store)
  end
end
