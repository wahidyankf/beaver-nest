defmodule BnestAppWeb.SifatAllahLiveUnitTest do
  @moduledoc """
  Unit tests for the `sifat_allah.feature` saved-progress scenarios. The production
  `SifatAllahLive` runs over the SifatAllah facade's record-backed progress store,
  which runs here over an in-memory record backend, so a rejected save and each
  storage note take the same path the learner's browser triggers.
  """

  use ExUnit.Case, async: false

  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestAppWeb.SifatAllahLive
  alias Phoenix.HTML.Safe
  alias Phoenix.LiveView.Socket

  setup do
    store = InMemoryRecordBackend.start()
    start_supervised!({Records, store: store})
    {:ok, store: store}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: A failed progress save says the saved progress is unchanged
  test "a failed progress save says the saved progress is unchanged", %{store: store} do
    {:ok, socket} = mount(account_user())
    {:noreply, socket} = event(socket, "start-learning", %{})
    {:noreply, socket} = event(socket, "remember-pair", %{})
    {:noreply, socket} = event(socket, "next-pair", %{})
    assert page_text(socket) =~ "6 dari 120 soal sudah hafal"

    InMemoryRecordBackend.fail_next_write(store)
    {:noreply, failed} = event(socket, "remember-pair", %{})

    assert page_text(failed) =~
             "Progress could not be saved. The previous saved progress is unchanged."

    {:ok, reloaded} = mount(account_user())
    assert page_text(reloaded) =~ "6 dari 120 soal sudah hafal"
    refute page_text(reloaded) =~ "12 dari 120 soal sudah hafal"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: The page says where progress is stored for this user
  test "the page says the account store for a signed-in child" do
    {:ok, socket} = mount(account_user())
    assert page_text(socket) =~ "Tersimpan aman untuk akun ini"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: The page says where progress is stored for this user
  test "the page says the browser store for the local user" do
    # Disconnected, as a page load is before its socket connects.
    socket = %Socket{
      view: SifatAllahLive,
      transport_pid: nil,
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_user: %{"migrationMode" => true, "userId" => "browser"}
      }
    }

    {:ok, mounted} = SifatAllahLive.mount(%{}, %{}, socket)
    assert page_text(mounted) =~ "Tersimpan di browser ini"
  end

  defp account_user do
    %{
      "userId" => "user-test-unit-sifat-allah",
      "displayUsername" => "test-user-unit-sifat-allah",
      "roles" => ["children"]
    }
  end

  defp mount(user) do
    socket = %Socket{
      view: SifatAllahLive,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}, current_user: user}
    }

    SifatAllahLive.mount(%{}, %{}, socket)
  end

  defp event(socket, name, params) do
    SifatAllahLive.handle_event(name, params, socket)
  end

  defp page_text(socket) do
    socket.assigns
    |> Map.delete(:__changed__)
    |> SifatAllahLive.render()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
