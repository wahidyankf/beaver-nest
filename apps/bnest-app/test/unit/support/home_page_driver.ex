defmodule BnestApp.Behaviour.UnitHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver

  alias BnestApp.Chat
  alias BnestApp.Codex.FixtureModels
  alias BnestApp.SifatAllah
  alias BnestAppWeb.SifatAllahLive
  alias Phoenix.HTML.Safe

  @impl true
  def open(context, "/chat") do
    render_chat(context, Chat.new())
  end

  def open(context, "/"), do: render_home(context)

  def open(context, "/apps/sifat-allah") do
    render_sifat_allah(context, sifat_state())
  end

  @impl true
  def brand_logo_visible?(context) do
    context.page
    |> LazyHTML.query("[data-role=brand-logo][src='/images/beaver-nest-logo.png']")
    |> Enum.any?()
  end

  @impl true
  def installable_as_app?(_context) do
    BnestAppWeb.Pwa.install_metadata() == %{
      manifest_path: "/manifest.webmanifest",
      service_worker_path: "/service-worker.js",
      icon_paths: ["/images/beaver-nest-192.png", "/images/beaver-nest-512.png"]
    }
  end

  @impl true
  def heading_visible?(context, heading) do
    context.page
    |> LazyHTML.query("h1")
    |> LazyHTML.text()
    |> Kernel.==(heading)
  end

  @impl true
  def text_visible?(context, text) do
    context.page
    |> LazyHTML.query("main")
    |> Enum.any?(fn element ->
      element
      |> LazyHTML.text()
      |> String.trim()
      |> String.contains?(text)
    end)
  end

  @impl true
  def chat_entry_link_visible?(context, label, path) do
    context.page
    |> LazyHTML.query("a[href='#{path}'] strong")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(label)
  end

  @impl true
  def model_selector_lists_all?(context) do
    context.page
    |> LazyHTML.query("[data-role=model-selector] option")
    |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))
    |> Kernel.==(FixtureModels.display_names())
  end

  @impl true
  def selected_model?(context, display_name) do
    context.page
    |> LazyHTML.query("[data-role=model-selector] option[selected]")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(display_name)
  end

  @impl true
  def effort_selector_lists_supported?(context) do
    model = FixtureModels.fetch_by_id!(context.chat.model)

    context.page
    |> LazyHTML.query("[data-role=effort-selector] option")
    |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))
    |> Kernel.==(Enum.map(model.supported_reasoning_efforts, &effort_label/1))
  end

  @impl true
  def selected_effort?(context, effort) do
    context.page
    |> LazyHTML.query("[data-role=effort-selector] option[selected]")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(effort)
  end

  @impl true
  def model_selector_available?(context) do
    selector = LazyHTML.query(context.page, "[data-role=model-selector]")
    not Enum.empty?(selector) and selector |> LazyHTML.attribute("disabled") |> Enum.empty?()
  end

  @impl true
  def model_selector_unavailable?(context),
    do: not model_selector_available?(context)

  @impl true
  def effort_selector_available?(context) do
    selector = LazyHTML.query(context.page, "[data-role=effort-selector]")
    not Enum.empty?(selector) and selector |> LazyHTML.attribute("disabled") |> Enum.empty?()
  end

  @impl true
  def effort_selector_unavailable?(context),
    do: not effort_selector_available?(context)

  @impl true
  def select_model(context, display_name) do
    model = FixtureModels.fetch_by_display_name!(display_name)

    effort =
      if context.chat.reasoning_effort in model.supported_reasoning_efforts,
        do: context.chat.reasoning_effort,
        else: "medium"

    {:ok, chat} =
      Chat.select_model(context.chat, model.id, effort)

    render_chat(context, chat)
  end

  @impl true
  def select_effort(context, effort) do
    {:ok, chat} = Chat.select_model(context.chat, context.chat.model, String.downcase(effort))
    render_chat(context, chat)
  end

  @impl true
  def conversation_empty?(context) do
    context.page
    |> LazyHTML.query("[data-role=message]")
    |> Enum.empty?()
  end

  @impl true
  def composer_available?(context) do
    enabled?(context.page, "textarea") and enabled?(context.page, ".send-button")
  end

  @impl true
  def composer_unavailable?(context) do
    not enabled?(context.page, "textarea") and not enabled?(context.page, ".send-button")
  end

  @impl true
  def clear_chat_control_available?(context) do
    controls = LazyHTML.query(context.page, "[data-role=clear-chat]")
    not Enum.empty?(controls) and controls |> LazyHTML.attribute("disabled") |> Enum.empty?()
  end

  @impl true
  def attempt_empty_message(context) do
    {:error, chat} = Chat.submit(context.chat, "   ")
    render_chat(context, chat)
  end

  @impl true
  def send_message(context, message) do
    {:ok, chat} = Chat.submit(context.chat, message)
    render_chat(context, chat)
  end

  @impl true
  def submit_with_shift_enter(context, message), do: send_message(context, message)

  @impl true
  def attempt_message_before_finished(context, message) do
    {:error, chat} = Chat.submit(context.chat, message)
    render_chat(context, chat)
  end

  @impl true
  def visitor_message_visible?(context, message) do
    context.page
    |> LazyHTML.query("[data-role=user-message]")
    |> Enum.any?(fn element -> element |> LazyHTML.text() |> String.trim() == message end)
  end

  @impl true
  def visitor_message_absent?(context, message) do
    not visitor_message_visible?(context, message)
  end

  @impl true
  def stream_codex_response(context) do
    chat =
      context.chat
      |> Chat.put_thread_id("fixture-thread")
      |> Chat.update_assistant("Fixture response")
      |> Chat.update_assistant("Fixture response complete.")
      |> Chat.complete()

    {:ok, snapshot} = Chat.snapshot(chat)

    context =
      context
      |> Map.put(:persisted_chat, Jason.encode!(snapshot))
      |> render_chat(chat)

    {assistant_update_count(context) >= 2, context}
  end

  @impl true
  def second_codex_response_visible?(context) do
    context.page
    |> LazyHTML.query("[data-role=assistant-message]")
    |> Enum.count()
    |> Kernel.==(2)
  end

  @impl true
  def one_completed_codex_response_visible?(context) do
    context.page
    |> LazyHTML.query("[data-role=assistant-message][data-streaming=false]")
    |> Enum.count()
    |> Kernel.==(1)
  end

  @impl true
  def reject_message(context, message) do
    {:ok, chat} = Chat.submit(context.chat, message)
    render_chat(context, Chat.fail(chat, "Codex is not available."))
  end

  @impl true
  def report_codex_error(context, message) do
    render_chat(context, Chat.fail(context.chat, message))
  end

  @impl true
  def alert_visible?(context, message) do
    context.page
    |> LazyHTML.query("[role=alert]")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(message)
  end

  @impl true
  def reload(%{persisted_chat: encoded} = context) do
    {:ok, snapshot} = Jason.decode(encoded)
    {:ok, chat} = Chat.restore(snapshot)
    render_chat(context, chat)
  end

  def reload(%{sifat: state} = context) do
    render_sifat_allah(context, state)
  end

  @impl true
  def clear_chat(context) do
    context
    |> Map.delete(:persisted_chat)
    |> render_chat(Chat.new(context.chat.model, context.chat.reasoning_effort))
  end

  @impl true
  def study_mode_available?(context) do
    button_visible?(context.page, "Belajar 3 Pasangan")
  end

  @impl true
  def quiz_mode_available?(context), do: button_visible?(context.page, "Latihan Ujian")

  @impl true
  def start_learning(context) do
    context
    |> render_sifat_allah(
      context.sifat
      |> Map.put(:mode, :study)
      |> Map.put(:lesson_pairs, SifatAllah.lesson_pairs(context.sifat.progress))
      |> Map.put(:lesson_index, 0)
      |> Map.put(:feedback, nil)
    )
  end

  @impl true
  def remember_every_sifat_pair(context) do
    progress =
      Enum.reduce(SifatAllah.curriculum(), context.sifat.progress, fn pair, acc ->
        SifatAllah.remember(acc, pair.id)
      end)

    render_sifat_allah(context, %{
      context.sifat
      | progress: progress,
        mode: :dashboard,
        feedback: nil
    })
  end

  @impl true
  def swipe_study_card_left(context), do: move_lesson(context, 1)

  @impl true
  def swipe_study_card_right(context), do: move_lesson(context, -1)

  @impl true
  def return_to_mission(context) do
    render_sifat_allah(
      context,
      context.sifat |> Map.put(:mode, :dashboard) |> Map.put(:feedback, nil)
    )
  end

  @impl true
  def browser_back_to_mission(context), do: return_to_mission(context)

  @impl true
  def study_card_shows?(context, name, meaning) do
    card = LazyHTML.query(context.page, "[data-role=study-card]")
    text = LazyHTML.text(card)
    String.contains?(text, name) and String.contains?(text, meaning)
  end

  @impl true
  def study_card_colors_attributes?(context) do
    wajib? =
      context.page
      |> LazyHTML.query("[data-memory-color=wajib]")
      |> LazyHTML.attribute("data-memory-color")
      |> Enum.member?("wajib")

    mustahil? =
      context.page
      |> LazyHTML.query("[data-memory-color=mustahil]")
      |> LazyHTML.attribute("data-memory-color")
      |> Enum.member?("mustahil")

    wajib? and mustahil?
  end

  @impl true
  def mark_current_pair_remembered(context) do
    pair = current_pair(context.sifat)
    progress = SifatAllah.remember(context.sifat.progress, pair.id)

    context
    |> Map.put(:persisted_sifat_allah, Jason.encode!(progress))
    |> render_sifat_allah(
      context.sifat
      |> Map.put(:progress, progress)
      |> Map.put(:feedback, %{kind: :success, text: "Hebat!"})
    )
  end

  @impl true
  def progress_shows?(context, progress) do
    context.page
    |> LazyHTML.query(".sifat-stage")
    |> LazyHTML.text()
    |> String.trim()
    |> String.contains?(progress)
  end

  @impl true
  def start_quiz(context) do
    context
    |> render_sifat_allah(
      context.sifat
      |> Map.put(:mode, :quiz)
      |> Map.put(:quiz_pair, SifatAllah.quiz_pair(context.sifat.progress))
      |> Map.put(:quiz_kind, :wajib_meaning)
      |> Map.put(:quiz_scope, :all)
      |> Map.put(:feedback, nil)
    )
  end

  @impl true
  def quiz_answer_positions_vary?(context) do
    first_pair = context.sifat.quiz_pair
    second_pair = SifatAllah.next_pair(first_pair)

    answer_position(first_pair, :wajib_meaning) != answer_position(second_pair, :wajib_opposite)
  end

  @impl true
  def start_learned_review(context) do
    [pair | _rest] = SifatAllah.pairs_for(context.sifat.progress["learned_ids"])

    render_sifat_allah(
      context,
      context.sifat
      |> Map.put(:mode, :quiz)
      |> Map.put(:quiz_pair, pair)
      |> Map.put(:quiz_kind, :wajib_meaning)
      |> Map.put(:quiz_scope, :learned)
      |> Map.put(:feedback, nil)
    )
  end

  @impl true
  def start_focused_review(context) do
    [pair | _rest] = SifatAllah.review_pairs(context.sifat.progress)

    render_sifat_allah(
      context,
      context.sifat
      |> Map.put(:mode, :review)
      |> Map.put(:review_pair, pair)
      |> Map.put(:review_kind, :wajib_meaning)
      |> Map.put(:feedback, nil)
    )
  end

  @impl true
  def swipe_quiz_question_left(context), do: move_quiz_question(context, 1)

  @impl true
  def swipe_quiz_question_right(context), do: move_quiz_question(context, -1)

  @impl true
  def next_quiz_question(context) do
    quiz_kind = SifatAllah.next_question_kind(context.sifat.quiz_kind)

    render_sifat_allah(
      context,
      context.sifat
      |> Map.put(
        :quiz_pair,
        SifatAllah.next_unlearned_pair(context.sifat.progress, context.sifat.quiz_pair)
      )
      |> Map.put(:quiz_kind, quiz_kind)
      |> Map.put(:feedback, nil)
    )
  end

  @impl true
  def answer_quiz(context, answer) do
    pair = context.sifat.quiz_pair
    correct? = SifatAllah.correct_answer?(pair, context.sifat.quiz_kind, answer)

    progress =
      context.sifat.progress
      |> record_quiz_answer(pair, context.sifat.quiz_kind, correct?, context.sifat.quiz_scope)

    feedback =
      if correct?,
        do: %{kind: :success, text: "Betul!"},
        else: %{
          kind: :retry,
          text:
            "Belum tepat. Jawaban yang benar: #{SifatAllah.correct_answer(pair, context.sifat.quiz_kind)}. Nanti kita ulang lagi, ya."
        }

    context
    |> Map.put(:persisted_sifat_allah, Jason.encode!(progress))
    |> render_sifat_allah(
      context.sifat
      |> Map.put(:progress, progress)
      |> Map.put(:feedback, feedback)
    )
  end

  @impl true
  def answer_focused_review(context, answer) do
    pair = context.sifat.review_pair
    correct? = SifatAllah.correct_answer?(pair, context.sifat.review_kind, answer)

    progress =
      context.sifat.progress
      |> SifatAllah.record_answer(pair, context.sifat.review_kind, correct?)

    feedback =
      if correct? do
        %{kind: :success, text: "Mantap! #{pair.wajib} sudah kamu kuasai."}
      else
        %{
          kind: :retry,
          text:
            "Belum tepat. Jawaban yang benar: #{SifatAllah.correct_answer(pair, context.sifat.review_kind)}. Coba sekali lagi, ya."
        }
      end

    context
    |> Map.put(:persisted_sifat_allah, Jason.encode!(progress))
    |> render_sifat_allah(
      context.sifat
      |> Map.put(:progress, progress)
      |> Map.put(:feedback, feedback)
    )
  end

  @impl true
  def next_focused_review(context) do
    case SifatAllah.next_review_pair(context.sifat.progress, context.sifat.review_pair) do
      nil ->
        return_to_mission(context)

      pair ->
        review_kind = review_next_kind(context.sifat.review_pair, pair, context.sifat.review_kind)

        render_sifat_allah(
          context,
          context.sifat
          |> Map.put(:review_pair, pair)
          |> Map.put(:review_kind, review_kind)
          |> Map.put(:feedback, nil)
        )
    end
  end

  @impl true
  def revision_list_contains?(context, name) do
    context.page
    |> LazyHTML.query("[data-testid=sifat-allah-revision-list]")
    |> LazyHTML.text()
    |> String.contains?(name)
  end

  defp render_chat(context, chat) do
    page =
      %{
        chat: chat,
        models: FixtureModels.all(),
        form: Phoenix.Component.to_form(%{"prompt" => ""}, as: :chat)
      }
      |> BnestAppWeb.ChatLive.render()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> LazyHTML.from_fragment()

    context
    |> Map.put(:chat, chat)
    |> Map.put(:page, page)
  end

  defp render_home(context) do
    page =
      %{flash: %{}}
      |> BnestAppWeb.PageHTML.home()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> LazyHTML.from_fragment()

    Map.put(context, :page, page)
  end

  defp render_sifat_allah(context, state) do
    page =
      state
      |> SifatAllahLive.render()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> LazyHTML.from_fragment()

    context
    |> Map.put(:sifat, state)
    |> Map.put(:page, page)
  end

  defp sifat_state(overrides \\ []) do
    Map.merge(
      %{
        progress: SifatAllah.progress(),
        mode: :dashboard,
        lesson_pairs: [],
        lesson_index: 0,
        quiz_pair: nil,
        quiz_kind: :wajib_meaning,
        quiz_scope: :all,
        review_pair: nil,
        review_kind: :wajib_meaning,
        feedback: nil
      },
      Map.new(overrides)
    )
  end

  defp current_pair(state), do: Enum.at(state.lesson_pairs, state.lesson_index)

  defp record_quiz_answer(progress, pair, kind, correct?, _scope),
    do: SifatAllah.record_answer(progress, pair, kind, correct?)

  defp move_lesson(context, direction) do
    lesson_index =
      context.sifat.lesson_index
      |> Kernel.+(direction)
      |> max(0)
      |> min(length(context.sifat.lesson_pairs) - 1)

    render_sifat_allah(context, Map.put(context.sifat, :lesson_index, lesson_index))
  end

  defp move_quiz_question(context, 1) do
    quiz_kind = SifatAllah.next_question_kind(context.sifat.quiz_kind)

    render_sifat_allah(
      context,
      context.sifat
      |> Map.put(:quiz_pair, SifatAllah.next_pair(context.sifat.quiz_pair))
      |> Map.put(:quiz_kind, quiz_kind)
      |> Map.put(:feedback, nil)
    )
  end

  defp move_quiz_question(context, -1) do
    quiz_kind = SifatAllah.previous_question_kind(context.sifat.quiz_kind)

    render_sifat_allah(
      context,
      context.sifat
      |> Map.put(
        :quiz_pair,
        SifatAllah.previous_unlearned_pair(context.sifat.progress, context.sifat.quiz_pair)
      )
      |> Map.put(:quiz_kind, quiz_kind)
      |> Map.put(:feedback, nil)
    )
  end

  defp review_next_kind(%{id: id}, %{id: id}, kind), do: kind
  defp review_next_kind(_current_pair, _next_pair, kind), do: SifatAllah.next_question_kind(kind)

  defp answer_position(pair, kind) do
    pair
    |> SifatAllah.answer_options(kind)
    |> Enum.find_index(&(&1 == SifatAllah.correct_answer(pair, kind)))
  end

  defp button_visible?(page, label) do
    page
    |> LazyHTML.query("button")
    |> Enum.any?(fn button -> button |> LazyHTML.text() |> String.contains?(label) end)
  end

  defp enabled?(page, selector) do
    page
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("disabled")
    |> Enum.empty?()
  end

  defp assistant_update_count(context) do
    context.page
    |> LazyHTML.query("[data-role=assistant-message]")
    |> Enum.at(-1)
    |> LazyHTML.attribute("data-update-count")
    |> List.first()
    |> String.to_integer()
  end

  defp effort_label("xhigh"), do: "XHigh"
  defp effort_label(effort), do: String.capitalize(effort)
end
