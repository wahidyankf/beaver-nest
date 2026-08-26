defmodule BnestApp.ApplicationTest do
  use ExUnit.Case, async: false

  test "propagates configuration changes to the endpoint" do
    assert :ok = BnestApp.Application.config_change(%{}, [], [])
  end

  test "starts one repository against the marked configured root" do
    configured_root = Application.fetch_env!(:bnest_app, :runtime_root)
    store = BnestApp.DataRepository.store()
    on_exit(fn -> Application.put_env(:bnest_app, :runtime_root, configured_root) end)

    assert store.root == configured_root
    assert {:ok, %{path: ^configured_root}} = BnestApp.TestRuntimeRoot.validate(configured_root)

    Application.put_env(:bnest_app, :runtime_root, BnestApp.TestRuntimeRoot.production_root())
    assert BnestApp.DataRepository.store().root == configured_root
  end
end
