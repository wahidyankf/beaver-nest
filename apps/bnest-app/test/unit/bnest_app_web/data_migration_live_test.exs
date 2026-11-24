defmodule BnestAppWeb.DataMigrationLiveTest do
  @moduledoc """
  Unit tests for the `centralized_data.feature` migration scenarios. The production
  `DataMigrationLive` runs over the Storage facade's record repository, which runs
  here over an in-memory record backend, so the browser report and the confirmation
  take the same path the page's hook triggers, without touching the disk.
  """

  use ExUnit.Case, async: false

  alias BnestApp.Storage.Import
  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestAppWeb.DataMigrationLive
  alias Phoenix.HTML.Safe
  alias Phoenix.LiveView.Socket

  setup do
    store = InMemoryRecordBackend.start()
    start_supervised!({Records, store: store})
    {:ok, store: store}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: The migration page lists each recognized browser source
  test "the migration page lists each recognized browser source", %{store: _store} do
    sources = [
      %{
        "storageArea" => "sessionStorage",
        "storageKey" => "bnest.chat.v1",
        "present" => true,
        "payload" => "{}"
      },
      %{
        "storageArea" => "localStorage",
        "storageKey" => "bnest.sifat-allah.v1",
        "present" => true,
        "payload" => "{}"
      },
      %{"storageArea" => "localStorage", "storageKey" => "phx:theme", "present" => false},
      %{
        "storageArea" => "localStorage",
        "storageKey" => "unknown.key",
        "present" => true,
        "payload" => "keep"
      }
    ]

    {:ok, mounted} = DataMigrationLive.mount(%{}, %{}, fresh_socket())

    {:noreply, socket} =
      DataMigrationLive.handle_event("browser-sources", %{"sources" => sources}, mounted)

    page = render(socket)
    cards = page |> LazyHTML.query(".identity-account-card") |> Enum.map(&LazyHTML.text/1)

    assert Enum.any?(cards, &(&1 =~ "Chat conversation" and &1 =~ "Ready to preserve"))
    assert Enum.any?(cards, &(&1 =~ "Sifat Allah progress" and &1 =~ "Ready to preserve"))
    assert Enum.any?(cards, &(&1 =~ "Theme preference" and &1 =~ "Uses system default"))
    refute page |> LazyHTML.text() |> String.contains?("unknown.key")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each import outcome shows its label and its status
  test "an accepted import shows its label and status" do
    assert confirm(chat_payload()) == ["Chat conversation: accepted and verified"]
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each import outcome shows its label and its status
  test "a rejected import shows its label and status" do
    assert confirm(%{chat_payload() | "payload" => "{malformed"}) == [
             "Chat conversation: rejected safely; browser source retained"
           ]
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each import outcome shows its label and its status
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each retryable or stale import outcome shows its label and its status
  test "a retryable import shows its label and status", %{store: store} do
    InMemoryRecordBackend.fail_next_write(store)

    assert confirm(chat_payload()) == [
             "Chat conversation: not completed; retry without re-entering data"
           ]
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each import outcome shows its label and its status
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/centralized_data.feature: A stale browser cannot overwrite a newer centralized record
  test "a stale import shows its label and status", %{store: store} do
    {:ok, _accepted} = Import.browser(store, "user-unit", chat_payload())

    stale = %{
      chat_payload()
      | "payload" => String.replace(chat_payload()["payload"], "fixture-model", "stale")
    }

    assert confirm(stale) == [
             "Chat conversation: newer server data exists; refresh before retrying"
           ]
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: A browser acting as the local user is told to log in before importing
  test "a browser acting as the local user is told to log in before importing" do
    socket = %Socket{
      view: DataMigrationLive,
      transport_pid: self(),
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_user: %{"migrationMode" => true, "userId" => "browser"}
      }
    }

    {:ok, socket} = DataMigrationLive.mount(%{}, %{}, socket)

    assert match?({:redirect, %{to: "/"}}, socket.redirected)

    assert Phoenix.Flash.get(socket.assigns.flash, :error) ==
             "Log in before importing browser data."
  end

  defp confirm(source) do
    {:ok, mounted} = DataMigrationLive.mount(%{}, %{}, fresh_socket())

    {:noreply, reported} =
      DataMigrationLive.handle_event(
        "browser-sources",
        %{"sources" => [Map.put(source, "present", true)]},
        mounted
      )

    {:noreply, confirmed} = DataMigrationLive.handle_event("confirm-imports", %{}, reported)

    confirmed
    |> render()
    |> LazyHTML.query("[aria-live=polite] p")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp chat_payload do
    %{
      "storageArea" => "sessionStorage",
      "storageKey" => "bnest.chat.v1",
      "payload" =>
        Jason.encode!(%{
          "version" => 2,
          "thread_id" => nil,
          "model" => "fixture-model",
          "reasoning_effort" => "medium",
          "messages" => []
        })
    }
  end

  defp fresh_socket do
    %Socket{
      view: DataMigrationLive,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}, current_user: %{"userId" => "user-unit"}}
    }
  end

  defp render(socket) do
    socket.assigns
    |> Map.delete(:__changed__)
    |> DataMigrationLive.render()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> LazyHTML.from_fragment()
  end
end
