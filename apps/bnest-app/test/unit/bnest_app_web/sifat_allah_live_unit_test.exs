defmodule BnestAppWeb.SifatAllahLiveUnitTest do
  @moduledoc """
  Unit tests for the `sifat_allah.feature` saved-progress scenarios. The production
  `SifatAllahLive` runs over the SifatAllah facade's record-backed progress store,
  which runs here over an in-memory record backend, so a rejected save and each
  storage note take the same path the learner's browser triggers.
  """

  use ExUnit.Case, async: false

  alias BnestApp.SifatAllah.Domain.Quiz
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

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: A child opens the revision dashboard
  test "a child opens the revision dashboard" do
    {:ok, socket} = mount(account_user())

    assert socket.assigns.mode == :dashboard
    assert page_text(socket) =~ "Misi Hafal 40 Sifat Allah"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: A child resets saved progress from the mission
  test "a child resets saved progress from the mission" do
    {:ok, socket} = mount(account_user())
    {:noreply, studying} = event(socket, "start-learning", %{})
    {:noreply, remembered} = event(studying, "remember-pair", %{})
    assert remembered.assigns.progress["learned_ids"] != []

    {:noreply, asked} = event(remembered, "ask-reset-progress", %{})
    assert asked.assigns.reset_confirmation? == true

    {:noreply, reset} = event(asked, "reset-progress", %{})
    assert reset.assigns.progress["learned_ids"] == []
    assert reset.assigns.reset_confirmation? == false

    {:ok, reloaded} = mount(account_user())
    assert reloaded.assigns.progress["learned_ids"] == []
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: A child swipes through a learning session
  test "a child swipes through a learning session" do
    {:ok, socket} = mount(account_user())
    {:noreply, studying} = event(socket, "start-learning", %{})
    assert studying.assigns.mode == :study
    assert studying.assigns.lesson_index == 0

    {:noreply, swiped} = event(studying, "swipe-study", %{"direction" => "left"})
    assert swiped.assigns.lesson_index == 1

    {:noreply, back} = event(swiped, "swipe-study", %{"direction" => "right"})
    assert back.assigns.lesson_index == 0
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: A child can return to the mission while learning
  test "a child can return to the mission while learning" do
    {:ok, socket} = mount(account_user())
    {:noreply, studying} = event(socket, "start-learning", %{})
    assert studying.assigns.mode == :study

    {:noreply, mission} = event(studying, "dashboard", %{})
    assert mission.assigns.mode == :dashboard
    assert page_text(mission) =~ "Misi Hafal 40 Sifat Allah"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: A child receives kind feedback for a correct quiz answer
  test "a child receives kind feedback for a correct quiz answer" do
    {:ok, socket} = mount(account_user())
    {:noreply, quizzing} = event(socket, "start-quiz", %{})
    pair = quizzing.assigns.quiz_pair
    kind = quizzing.assigns.quiz_kind

    {:noreply, answered} =
      event(quizzing, "answer", %{"answer" => Quiz.correct_answer(pair, kind)})

    assert answered.assigns.feedback == %{kind: :success, text: "Betul!"}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: A quiz locks one answer and moves on automatically
  test "a quiz locks one answer and moves on automatically" do
    {:ok, socket} = mount(account_user())
    {:noreply, quizzing} = event(socket, "start-quiz", %{})
    pair = quizzing.assigns.quiz_pair
    kind = quizzing.assigns.quiz_kind

    {:noreply, answered} =
      event(quizzing, "answer", %{"answer" => Quiz.correct_answer(pair, kind)})

    assert answered.assigns.feedback != nil
    token = answered.assigns.auto_advance_token

    {:noreply, locked} = event(answered, "answer", %{"answer" => "a wrong answer"})
    assert locked.assigns.feedback == answered.assigns.feedback

    {:noreply, advanced} = SifatAllahLive.handle_info({:auto_advance, :quiz, token}, answered)
    assert advanced.assigns.feedback == nil
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: A child keeps the current quiz question after a reload
  test "a child keeps the current quiz question after a reload" do
    {:ok, socket} = mount(account_user())
    {:noreply, quizzing} = event(socket, "start-quiz", %{})
    pair_id = quizzing.assigns.quiz_pair.id
    kind = quizzing.assigns.quiz_kind

    {:ok, reloaded} = mount(account_user())
    assert reloaded.assigns.mode == :quiz
    assert reloaded.assigns.quiz_pair.id == pair_id
    assert reloaded.assigns.quiz_kind == kind
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: A child swipes through quiz questions
  test "a child swipes through quiz questions" do
    {:ok, socket} = mount(account_user())
    {:noreply, quizzing} = event(socket, "start-quiz", %{})
    {pair, kind} = {quizzing.assigns.quiz_pair, quizzing.assigns.quiz_kind}

    {:noreply, swiped} = event(quizzing, "swipe-quiz", %{"direction" => "left"})
    assert {swiped.assigns.quiz_pair.id, swiped.assigns.quiz_kind} != {pair.id, kind}

    {:noreply, back} = event(swiped, "swipe-quiz", %{"direction" => "right"})
    assert {back.assigns.quiz_pair.id, back.assigns.quiz_kind} == {pair.id, kind}
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
