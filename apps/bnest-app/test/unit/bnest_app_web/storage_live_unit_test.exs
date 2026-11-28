defmodule BnestAppWeb.StorageLiveUnitTest do
  @moduledoc """
  Unit tests for the `sqlite_storage.feature` migration-control and folder-lock
  scenarios. The production `StorageLive` runs over the Storage facade's
  in-memory ports, so `move_data` and `retry_migration` take the same path the
  administrator's browser triggers, without touching the file system.
  """

  use ExUnit.Case, async: false

  alias BnestApp.Storage
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestApp.Test.InMemory.StoragePorts.FlatSource
  alias BnestAppWeb.StorageLive
  alias Phoenix.HTML.Safe
  alias Phoenix.LiveView.Socket

  @in_memory_flat_root "/in-memory/flat"
  @unit_admin %{
    "userId" => "test-user-unit-admin",
    "displayUsername" => "test-user-unit-admin",
    "roles" => ["admin"]
  }

  setup do
    previous_ports = StoragePorts.install()
    on_exit(fn -> StoragePorts.restore(previous_ports) end)

    previous_root = Application.get_env(:bnest_app, :runtime_root)
    Application.put_env(:bnest_app, :runtime_root, @in_memory_flat_root)

    on_exit(fn ->
      if is_nil(previous_root),
        do: Application.delete_env(:bnest_app, :runtime_root),
        else: Application.put_env(:bnest_app, :runtime_root, previous_root)
    end)

    :ok
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature: Move data and Retry migration start or retry the migration
  test "Move data blocks on the malformed source and retry activates after repair" do
    FlatSource.put_files(@in_memory_flat_root, fixture_files() ++ [malformed_source()])

    assert control_label(render_storage()) == "Move data"

    {:noreply, _socket} = StorageLive.handle_event("move_data", %{}, storage_socket())
    # The production adapter derives `migration_started?` from the ledger; the
    # in-memory double answers from this key, so the test seeds it as the run
    # it just recorded would.
    StoragePorts.put(:started?, true)

    page = render_storage()
    assert status_of(page) == "Blocked — retry available"
    assert control_label(page) == "Retry migration"

    FlatSource.put_files(@in_memory_flat_root, fixture_files())
    {:noreply, _socket} = StorageLive.handle_event("retry_migration", %{}, storage_socket())

    assert status_of(render_storage()) == "SQLite active"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature: The storage status reads Not started, Blocked, or SQLite active
  test "the storage status reads Not started, Blocked, or SQLite active" do
    assert status_of(render_storage()) == "Not started"

    FlatSource.put_files(@in_memory_flat_root, fixture_files() ++ [malformed_source()])
    {:noreply, _socket} = StorageLive.handle_event("move_data", %{}, storage_socket())
    StoragePorts.put(:started?, true)
    assert status_of(render_storage()) == "Blocked — retry available"

    FlatSource.put_files(@in_memory_flat_root, fixture_files())
    {:noreply, _socket} = StorageLive.handle_event("retry_migration", %{}, storage_socket())
    assert status_of(render_storage()) == "SQLite active"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature: The folder is locked once migration has started
  test "the folder is locked once migration has started" do
    FlatSource.put_files(@in_memory_flat_root, fixture_files())

    assert {:ok, _outcome, _report} = Storage.migrate(@in_memory_flat_root, false)
    StoragePorts.put(:started?, true)

    page = render_storage()

    assert page |> LazyHTML.query("input#directory[disabled]") |> Enum.any?()

    assert page
           |> LazyHTML.query("section[aria-label='Database folder'] button[disabled]")
           |> LazyHTML.text()
           |> String.contains?("Check folder")

    refute page |> LazyHTML.text() |> String.contains?("Create database")
  end

  defp render_storage do
    {:ok, socket} = StorageLive.mount(%{}, %{}, storage_socket())

    socket.assigns
    |> Map.delete(:__changed__)
    |> StorageLive.render()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> LazyHTML.from_fragment()
  end

  defp storage_socket do
    %Socket{
      view: StorageLive,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}, current_user: @unit_admin}
    }
  end

  defp status_of(page) do
    page
    |> LazyHTML.query("section[aria-label='Migration status'] strong")
    |> LazyHTML.text()
  end

  defp control_label(page) do
    page
    |> LazyHTML.query("section[aria-label='Migration status'] button")
    |> LazyHTML.text()
    |> String.trim()
  end

  # Pretty-printed, as a hand-edited flat file may be; mirrors the unit
  # driver's SQLite storage fixtures.
  defp fixture_files do
    Enum.map(fixture_entries(), fn {path, record} ->
      {path, Jason.encode!(record, pretty: true)}
    end)
  end

  defp fixture_entries do
    [
      {"users/user-test-z-fixture/preferences/theme.json",
       theme_fixture("user-test-z-fixture", "light")},
      {"users/user-test-a-fixture/preferences/theme.json",
       theme_fixture("user-test-a-fixture", "dark")}
    ]
  end

  defp theme_fixture(owner_id, theme) do
    %{
      "schemaVersion" => 1,
      "recordType" => "theme-preference",
      "ownerId" => owner_id,
      "sourceImportId" => nil,
      "revision" => 1,
      "theme" => theme,
      "updatedAt" => "2026-09-04T12:00:00Z"
    }
  end

  defp malformed_source,
    do: {"users/user-test-storage/preferences/theme.json", "{malformed"}
end
