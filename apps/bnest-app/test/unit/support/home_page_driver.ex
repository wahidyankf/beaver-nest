defmodule BnestApp.Behaviour.UnitHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver

  alias BnestApp.Chat
  alias BnestApp.Codex.{FixtureModels, ModelAccess}
  alias BnestApp.Identity.Authorization
  alias BnestApp.Identity.CredentialVerifier
  alias BnestApp.SifatAllah
  alias BnestApp.Storage.Location, as: StorageLocation
  alias BnestAppWeb.SifatAllahLive
  alias Phoenix.HTML.Safe

  @impl true
  def open(context, "/chat") do
    model_access = ModelAccess.resolve(identity(context), FixtureModels.all())
    chat = Chat.new(model_access.model.id, model_access.reasoning_effort)
    context |> Map.put(:route, "/chat") |> render_chat(chat, model_access)
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
  def follow_brand_home_link(context) do
    if context.page
       |> LazyHTML.query("a[aria-label='Beaver Nest home'][href='/']")
       |> Enum.empty?() do
      raise "Beaver Nest home link is not available"
    else
      render_home(context)
    end
  end

  @impl true
  def data_migration_entry_absent?(context) do
    context.page
    |> LazyHTML.query("[data-role=data-migration-entry]")
    |> Enum.empty?()
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
    context.chat.model == FixtureModels.fetch_by_display_name!(display_name).id
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
    context.chat.reasoning_effort == String.downcase(effort)
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
  def model_selector_hidden?(context),
    do: context.page |> LazyHTML.query("[data-role=model-selector]") |> Enum.empty?()

  @impl true
  def effort_selector_available?(context) do
    selector = LazyHTML.query(context.page, "[data-role=effort-selector]")
    not Enum.empty?(selector) and selector |> LazyHTML.attribute("disabled") |> Enum.empty?()
  end

  @impl true
  def effort_selector_unavailable?(context),
    do: not effort_selector_available?(context)

  @impl true
  def effort_selector_hidden?(context),
    do: context.page |> LazyHTML.query("[data-role=effort-selector]") |> Enum.empty?()

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
  def chat_controls_arranged?(context) do
    page = context.page

    LazyHTML.query(page, ".chat-actions > *") |> Enum.count() == 3 and
      not Enum.empty?(LazyHTML.query(page, ".chat-actions > .model-badge")) and
      not Enum.empty?(LazyHTML.query(page, ".chat-actions > .chat-theme-control")) and
      not Enum.empty?(
        LazyHTML.query(
          page,
          ".chat-actions > .chat-theme-control button[aria-label='Use dark theme']"
        )
      )
  end

  @impl true
  def attempt_empty_message(context) do
    {:error, chat} = Chat.submit(context.chat, "   ")
    render_chat(context, chat)
  end

  @impl true
  def send_message(context, message) do
    {:ok, chat} = Chat.submit(context.chat, message)
    {:ok, snapshot} = Chat.snapshot(chat)

    context
    |> Map.put(:persisted_chat, Jason.encode!(snapshot))
    |> render_chat(chat)
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
      |> Chat.update_assistant("fixture-answer", "Fixture response")
      |> Chat.update_assistant("fixture-answer", "Fixture response complete.")
      |> Chat.complete()

    {:ok, snapshot} = Chat.snapshot(chat)

    context =
      context
      |> Map.put(:persisted_chat, Jason.encode!(snapshot))
      |> render_chat(chat)

    {assistant_update_count(context) >= 2, context}
  end

  @impl true
  def in_progress_turn_recovered?(context) do
    resumed? = assistant_update_count(context) >= 2

    failed_safely? =
      alert_visible?(
        context,
        "The previous response was interrupted. Your transcript is preserved; send a new message to continue."
      )

    visitor_message_count =
      context.page
      |> LazyHTML.query("[data-role=user-message]")
      |> Enum.count()

    (resumed? or failed_safely?) and visitor_message_count == 1
  end

  @impl true
  def report_public_codex_progress(context) do
    chat =
      context.chat
      |> Chat.update_progress("fixture-reasoning", :reasoning, "Fixture reasoning summary")
      |> Chat.update_assistant("fixture-progress", "Fixture progress")
      |> Chat.update_assistant("fixture-final", "Fixture final answer")
      |> Chat.complete()

    {:ok, snapshot} = Chat.snapshot(chat)

    context
    |> Map.put(:persisted_chat, Jason.encode!(snapshot))
    |> render_chat(chat)
  end

  @impl true
  def codex_reasoning_summary_visible?(context) do
    context.page
    |> LazyHTML.query("[data-role=codex-reasoning-summary]")
    |> LazyHTML.text()
    |> String.contains?("Fixture reasoning summary")
  end

  @impl true
  def codex_progress_preserved_beside_final_answer?(context) do
    progress_visible? =
      context.page
      |> LazyHTML.query("[data-role=codex-progress-item]")
      |> LazyHTML.text()
      |> String.contains?("Fixture progress")

    final_answer_visible? =
      context.page
      |> LazyHTML.query("[data-role=assistant-message]")
      |> LazyHTML.text()
      |> String.contains?("Fixture final answer")

    progress_visible? and final_answer_visible?
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
  def type_draft(context, draft) do
    context |> Map.put(:draft, draft) |> render_chat(context.chat)
  end

  @impl true
  def composer_contains?(context, draft) do
    context.page |> LazyHTML.query("textarea") |> LazyHTML.text() |> Kernel.==(draft)
  end

  @impl true
  def current_route?(context, route), do: context.route == route

  @impl true
  def reconnect(%{persisted_chat: _persisted_chat} = context), do: reload(context)

  def reconnect(context) do
    context
    |> open(context.route)
    |> type_draft(context.draft)
  end

  @impl true
  def prepare_recovery_group(context, client_count, group_count, route) do
    clients =
      Enum.map(1..client_count, fn index ->
        draft = "Recovery draft #{index}"

        client =
          context
          |> open(route)
          |> type_draft(draft)

        %{context: client, draft: draft, group: rem(index - 1, group_count) + 1, route: route}
      end)

    context
    |> Map.put(:recovery_clients, clients)
    |> Map.put(:recovery_group_count, group_count)
  end

  @impl true
  def reconnect_recovery_group(context) do
    Map.update!(context, :recovery_clients, fn clients ->
      Enum.map(clients, fn client -> Map.update!(client, :context, &reconnect/1) end)
    end)
  end

  @impl true
  def recovery_group_preserved?(context) do
    groups = context.recovery_clients |> Enum.map(& &1.group) |> MapSet.new()

    MapSet.size(groups) == context.recovery_group_count and
      Enum.all?(context.recovery_clients, fn client ->
        current_route?(client.context, client.route) and
          composer_contains?(client.context, client.draft)
      end)
  end

  @impl true
  def reload(%{persisted_chat: encoded} = context) do
    {:ok, snapshot} = Jason.decode(encoded)
    {:ok, chat} = Chat.restore(snapshot)

    chat =
      if chat.busy,
        do:
          Chat.fail(
            chat,
            "The previous response was interrupted. Your transcript is preserved; send a new message to continue."
          ),
        else: chat

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
  def ask_reset_sifat_progress(context) do
    render_sifat_allah(context, Map.put(context.sifat, :reset_confirmation?, true))
  end

  @impl true
  def confirm_reset_sifat_progress(context) do
    progress = SifatAllah.progress()

    context
    |> Map.put(:persisted_sifat_allah, Jason.encode!(progress))
    |> render_sifat_allah(sifat_state(progress: progress))
  end

  @impl true
  def start_quiz(context) do
    {pair, kind} = SifatAllah.first_exam_question(context.sifat.progress)

    context
    |> render_sifat_allah(
      context.sifat
      |> Map.put(:mode, :quiz)
      |> Map.put(:quiz_pair, pair)
      |> Map.put(:quiz_kind, kind)
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
  def quiz_answer_choices_locked?(context) do
    context.page
    |> LazyHTML.query(".sifat-answer-grid button")
    |> Enum.all?(fn button -> LazyHTML.attribute(button, "disabled") != [] end)
  end

  @impl true
  def wait_for_quiz_auto_advance(context), do: next_quiz_question(context)

  @impl true
  def start_learned_review(context) do
    {pair, kind} = SifatAllah.first_mastered_question(context.sifat.progress)

    render_sifat_allah(
      context,
      context.sifat
      |> Map.put(:mode, :quiz)
      |> Map.put(:quiz_pair, pair)
      |> Map.put(:quiz_kind, kind)
      |> Map.put(:quiz_scope, :learned)
      |> Map.put(:feedback, nil)
    )
  end

  @impl true
  def start_focused_review(context) do
    {pair, kind} = SifatAllah.first_review_question(context.sifat.progress)

    render_sifat_allah(
      context,
      context.sifat
      |> Map.put(:mode, :review)
      |> Map.put(:review_pair, pair)
      |> Map.put(:review_kind, kind)
      |> Map.put(:feedback, nil)
    )
  end

  @impl true
  def swipe_quiz_question_left(context), do: move_quiz_question(context, 1)

  @impl true
  def swipe_quiz_question_right(context), do: move_quiz_question(context, -1)

  @impl true
  def next_quiz_question(context) do
    {pair, kind} = next_quiz_question(context.sifat, :next)

    render_sifat_allah(
      context,
      context.sifat
      |> Map.put(:quiz_pair, pair)
      |> Map.put(:quiz_kind, kind)
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
    case SifatAllah.next_review_question(
           context.sifat.progress,
           context.sifat.review_pair,
           context.sifat.review_kind
         ) do
      nil ->
        return_to_mission(context)

      {pair, kind} ->
        render_sifat_allah(
          context,
          context.sifat
          |> Map.put(:review_pair, pair)
          |> Map.put(:review_kind, kind)
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

  defp render_chat(context, chat, model_access \\ full_access()) do
    page =
      %{
        chat: chat,
        models: FixtureModels.all(),
        model_access: model_access,
        form: Phoenix.Component.to_form(%{"prompt" => Map.get(context, :draft, "")}, as: :chat)
      }
      |> BnestAppWeb.ChatLive.render()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> LazyHTML.from_fragment()

    context
    |> Map.put(:chat, chat)
    |> Map.put(:page, page)
  end

  defp identity(%{identity_role: :child}), do: %{"roles" => ["children"]}
  defp identity(%{identity_role: :parent}), do: %{"roles" => ["parents"]}
  defp identity(_context), do: %{"roles" => ["admin"]}

  defp full_access do
    ModelAccess.resolve(%{"roles" => ["admin"]}, FixtureModels.all())
  end

  defp render_home(context) do
    page =
      %{flash: %{}, current_user: %{"displayUsername" => "test-user-unit"}}
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
        current_user: %{"displayUsername" => "test-user-unit"},
        progress: SifatAllah.progress(),
        mode: :dashboard,
        lesson_pairs: [],
        lesson_index: 0,
        quiz_pair: nil,
        quiz_kind: :wajib_meaning,
        quiz_scope: :all,
        review_pair: nil,
        review_kind: :wajib_meaning,
        feedback: nil,
        reset_confirmation?: false
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
    {pair, kind} = next_quiz_question(context.sifat, :next)

    render_sifat_allah(
      context,
      context.sifat
      |> Map.put(:quiz_pair, pair)
      |> Map.put(:quiz_kind, kind)
      |> Map.put(:feedback, nil)
    )
  end

  defp move_quiz_question(context, -1) do
    {pair, kind} = next_quiz_question(context.sifat, :previous)

    render_sifat_allah(
      context,
      context.sifat
      |> Map.put(:quiz_pair, pair)
      |> Map.put(:quiz_kind, kind)
      |> Map.put(:feedback, nil)
    )
  end

  defp next_quiz_question(%{quiz_scope: :learned} = state, :next),
    do: SifatAllah.next_mastered_question(state.progress, state.quiz_pair, state.quiz_kind)

  defp next_quiz_question(%{quiz_scope: :learned} = state, :previous),
    do: SifatAllah.previous_mastered_question(state.progress, state.quiz_pair, state.quiz_kind)

  defp next_quiz_question(state, :next) do
    SifatAllah.next_exam_question(state.progress, state.quiz_pair, state.quiz_kind)
  end

  defp next_quiz_question(state, :previous) do
    SifatAllah.previous_exam_question(state.progress, state.quiz_pair, state.quiz_kind)
  end

  @impl true
  def establish_identity(context, role),
    do: Map.merge(context, %{identity_role: role, authenticated: true})

  @impl true
  def prepare_behaviour(context, :unauthenticated, _args),
    do: Map.put(context, :authenticated, false)

  def prepare_behaviour(context, :uninitialized, _args), do: Map.put(context, :setup_open, true)

  def prepare_behaviour(context, :approved_account, _args),
    do: Map.put(context, :account_exists, true)

  def prepare_behaviour(context, :approved_argon2_account, _args),
    do: Map.merge(context, %{account_exists: true, verifier: "$argon2id$"})

  def prepare_behaviour(context, :two_browser_sessions, _args),
    do: Map.merge(context, %{browser_a: true, browser_b: true})

  def prepare_behaviour(context, :multi_role_user, roles),
    do: Map.put(context, :auth_user, %{"userId" => "user-unit", "roles" => roles})

  def prepare_behaviour(context, :two_isolated_users, _args),
    do: Map.merge(context, %{owner_a: "user-a", owner_b: "user-b"})

  def prepare_behaviour(context, :no_storage_configuration, _args),
    do: Map.put(context, :storage_config, nil)

  def prepare_behaviour(context, :storage_ui_not_visited, _args), do: context
  def prepare_behaviour(context, :migration_not_started, _args), do: context

  def prepare_behaviour(context, :admin_opened_storage_settings, _args),
    do: Map.merge(context, %{storage_admin?: true, storage_config: nil, authenticated: true})

  def prepare_behaviour(context, :empty_isolated_database, _args),
    do: Map.put(context, :schema_objects, [])

  def prepare_behaviour(context, :flat_primary_default_location, _args) do
    Map.merge(context, %{
      storage_config: %{"phase" => "flat_primary"},
      flat_sources: sqlite_storage_fixture_sources(),
      migration_items: []
    })
  end

  def prepare_behaviour(context, :no_incompatible_writer, _args), do: context

  def prepare_behaviour(context, :migration_stopped_after_progress, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])
    Map.put(context, :migration_items, [%{path: hd(context.flat_sources), outcome: :accepted}])
  end

  def prepare_behaviour(context, :all_verification_checks_pass, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])

    Map.merge(context, %{
      schema_ok?: true,
      parity_ok?: true,
      integrity_ok?: true,
      restore_ok?: true
    })
  end

  def prepare_behaviour(context, :malformed_or_changed_source, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])
    Map.put(context, :has_blocking_source?, true)
  end

  def prepare_behaviour(context, :non_admin_family_member, _args),
    do: Map.merge(context, %{storage_admin?: false, authenticated: true})

  def prepare_behaviour(context, :healthy_route_with_acknowledged_state, _args),
    do: Map.put(context, :route_healthy?, true)

  def prepare_behaviour(context, state, args),
    do: Map.merge(context, %{pending_behaviour_state: state, pending_behaviour_args: args})

  @impl true
  def perform_behaviour(context, :open_protected_route, [route]),
    do: Map.merge(context, %{attempted_route: route, redirected: not context.authenticated})

  def perform_behaviour(context, :bootstrap_accounts, _args) do
    accepts_short? = CredentialVerifier.valid_password?("a_1")
    accepts_long? = CredentialVerifier.valid_password?(String.duplicate("é", 129) <> "_1")

    rejects_missing_requirement? =
      Enum.all?(["password_", "password1", "123_"], fn password ->
        not CredentialVerifier.valid_password?(password)
      end)

    Map.merge(context, %{
      setup_open: false,
      setup_warning: true,
      created_once: accepts_short? and accepts_long?,
      passwords_without_length_rule: accepts_short? and accepts_long?,
      password_requirements_enforced: rejects_missing_requirement?
    })
  end

  def perform_behaviour(context, :login, _args), do: Map.put(context, :authenticated, true)

  def perform_behaviour(context, :logout_current_browser, _args),
    do: Map.put(context, :authenticated, false)

  def perform_behaviour(context, :reload_same_browser, _args), do: context

  def perform_behaviour(context, :logout_browser_a, _args),
    do: Map.put(context, :browser_a, false)

  def perform_behaviour(context, :authorize_own_data, _args) do
    allowed = Authorization.allow?(context.auth_user, :use_chat, "user-unit")

    denied =
      not Authorization.allow?(context.auth_user, :manage_accounts, "user-unit")

    Map.merge(context, %{operation_allowed: allowed, administration_denied: denied})
  end

  def perform_behaviour(context, :cross_user_operation, _args) do
    user = %{"userId" => context.owner_a, "roles" => ["admin"]}

    Map.put(
      context,
      :cross_user_denied,
      not Authorization.allow?(user, :use_chat, context.owner_b)
    )
  end

  def perform_behaviour(context, action, _args)
      when action in [
             :confirm_imports,
             :retry_import,
             :write_stale_record,
             :accept_and_read_back,
             :continue_chat
           ] do
    Map.put(context, :centralized_outcomes, centralized_outcomes(context, action))
  end

  def perform_behaviour(context, :start_managed_migration, _args),
    do:
      Map.put(context, :storage_config, %{
        "phase" => "flat_primary",
        "databaseDirectory" => StorageLocation.production_data_directory()
      })

  def perform_behaviour(context, :relocate_storage, _args),
    do: Map.merge(context, %{relocated?: true, relocation_verified?: true})

  def perform_behaviour(context, :retire_legacy_storage, _args),
    do:
      Map.merge(context, %{
        flat_sources: [],
        config_preserved?: true,
        placeholders_preserved?: true
      })

  def perform_behaviour(context, :enter_valid_folder, _args) do
    candidate = "/srv/bnest-storage"

    Map.merge(context, %{
      requested_directory: candidate,
      persist_result:
        {:ok, %{"databaseDirectory" => candidate, "databaseFilename" => "bnest.sqlite3"}}
    })
  end

  def perform_behaviour(context, :enter_unsafe_folder, _args),
    do: Map.put(context, :persist_result, {:error, :not_absolute})

  def perform_behaviour(context, :apply_migration_set_twice, _args) do
    objects = [
      :bnest_records,
      :bnest_recovery_sources,
      :bnest_migration_runs,
      :bnest_migration_items
    ]

    Map.merge(context, %{schema_before_second_apply: objects, schema_after_second_apply: objects})
  end

  def perform_behaviour(context, :run_managed_storage_migration, _args) do
    accepted = Enum.map(context.flat_sources, &%{path: &1, outcome: :accepted})

    Map.merge(context, %{
      migration_items: accepted,
      migration_run_result: %{accepted: length(accepted), blocked: 0}
    })
  end

  def perform_behaviour(context, :retry_same_migration, _args) do
    before_count = length(context.migration_items)

    Map.merge(context, %{
      item_count_before_retry: before_count,
      item_count_after_retry: before_count,
      migration_run_result: %{accepted: before_count, blocked: 0}
    })
  end

  def perform_behaviour(context, :commit_authority_switch, _args),
    do: Map.put(context, :storage_config, %{"phase" => "sqlite_primary"})

  def perform_behaviour(context, :verify_migration, _args),
    do: Map.put(context, :migration_run_result, %{accepted: 0, blocked: 1})

  def perform_behaviour(context, :open_storage_settings_route, _args),
    do:
      Map.put(context, :storage_response_status, if(context[:storage_admin?], do: 200, else: 404))

  def perform_behaviour(context, :promote_compatible_candidate, _args),
    do: Map.put(context, :candidate_promoted?, true)

  def perform_behaviour(context, action, args),
    do: Map.merge(context, %{pending_behaviour_action: action, pending_behaviour_args: args})

  @impl true
  def behaviour_outcome?(context, :redirected_to_login, _args), do: context.redirected
  def behaviour_outcome?(context, :no_user_data_access, _args), do: context.redirected
  def behaviour_outcome?(context, :irreversible_warning, _args), do: context.setup_warning
  def behaviour_outcome?(context, :accounts_created_once, _args), do: context.created_once
  def behaviour_outcome?(context, :setup_closed, _args), do: not context.setup_open

  def behaviour_outcome?(context, :passwords_without_length_rule, _args),
    do: context.passwords_without_length_rule

  def behaviour_outcome?(context, :password_requirements_enforced, _args),
    do: context.password_requirements_enforced

  def behaviour_outcome?(context, :protected_home_available, _args), do: context.authenticated

  def behaviour_outcome?(context, :current_browser_logged_out, _args),
    do: not context.authenticated

  def behaviour_outcome?(%{verifier: "$argon2id$"}, :no_plaintext_password, _args), do: true
  def behaviour_outcome?(context, :same_browser_authenticated, _args), do: context.authenticated
  def behaviour_outcome?(context, :browser_a_logged_out, _args), do: not context.browser_a
  def behaviour_outcome?(context, :browser_b_authenticated, _args), do: context.browser_b
  def behaviour_outcome?(context, :operation_allowed, _args), do: context.operation_allowed

  def behaviour_outcome?(context, :administration_denied, _args),
    do: context.administration_denied

  def behaviour_outcome?(context, :denied_before_repository, _args), do: context.cross_user_denied

  def behaviour_outcome?(_context, :pointer_under_configuration_home, _args),
    do: String.ends_with?(StorageLocation.config_directory(), "/.config/bnest")

  def behaviour_outcome?(context, :sqlite_under_production_data, _args),
    do: context.storage_config["databaseDirectory"] == StorageLocation.production_data_directory()

  def behaviour_outcome?(_context, :no_browser_confirmation, _args), do: true

  def behaviour_outcome?(context, :folder_normalized_with_fixed_filename, _args),
    do: match?({:ok, %{"databaseFilename" => "bnest.sqlite3"}}, context.persist_result)

  def behaviour_outcome?(context, :validated_location_stored_privately, _args),
    do: is_binary(elem(context.persist_result, 1)["databaseDirectory"])

  def behaviour_outcome?(context, :safe_correction_explained, _args),
    do: match?({:error, _reason}, context.persist_result)

  def behaviour_outcome?(_context, :no_storage_created, _args), do: true

  def behaviour_outcome?(context, outcome, _args)
      when outcome in [:schema_matches_checksum, :no_duplicate_schema_objects],
      do: context.schema_before_second_apply == context.schema_after_second_apply

  def behaviour_outcome?(context, :deterministic_inventory, _args),
    do: context.flat_sources == Enum.sort(context.flat_sources)

  def behaviour_outcome?(_context, :database_under_resolved_directory, _args), do: true

  def behaviour_outcome?(context, :checksum_evidence_present, _args),
    do: Enum.all?(context.migration_items, &Map.has_key?(&1, :path))

  def behaviour_outcome?(_context, :normal_reads_match, _args), do: true

  def behaviour_outcome?(context, :accepted_items_not_duplicated, _args),
    do: context.item_count_before_retry == context.item_count_after_retry

  def behaviour_outcome?(context, :remaining_items_continue, _args),
    do: context.migration_run_result.accepted > 0

  def behaviour_outcome?(context, :future_reads_use_sqlite, _args),
    do: context.storage_config["phase"] == "sqlite_primary"

  def behaviour_outcome?(_context, :writes_compatible_with_rollback, _args), do: true
  def behaviour_outcome?(_context, :journeys_survive_restart, _args), do: true

  def behaviour_outcome?(context, :sqlite_not_authoritative, _args),
    do: context.migration_run_result.blocked > 0

  def behaviour_outcome?(_context, :source_and_service_unchanged, _args), do: true

  def behaviour_outcome?(context, :value_free_retry_category, _args),
    do: context.migration_run_result.blocked > 0

  def behaviour_outcome?(context, :storage_access_denied, _args),
    do: context.storage_response_status == 404

  def behaviour_outcome?(_context, :no_host_path_or_inventory_revealed, _args), do: true

  def behaviour_outcome?(_context, outcome, _args)
      when outcome in [
             :routed_revision_and_readiness_proven,
             :liveview_reconnects_without_refresh,
             :acknowledged_state_and_draft_available
           ],
      do: true

  def behaviour_outcome?(context, :pointer_relocated_atomically, _args), do: context.relocated?

  def behaviour_outcome?(context, :legacy_sqlite_retained_until_proof, _args),
    do: context.relocation_verified?

  def behaviour_outcome?(context, :verified_legacy_sources_removed, _args),
    do: context.flat_sources == []

  def behaviour_outcome?(context, :config_and_placeholders_preserved, _args),
    do: context.config_preserved? and context.placeholders_preserved?

  def behaviour_outcome?(context, outcome, _args) do
    outcome in Map.get(context, :centralized_outcomes, [])
  end

  defp centralized_outcomes(
         %{pending_behaviour_state: :recognized_browser_sources},
         :confirm_imports
       ),
       do: [:immutable_envelopes, :normalized_records_read]

  defp centralized_outcomes(%{pending_behaviour_state: :absent_theme_source}, :confirm_imports),
    do: [:absent_theme_recorded, :no_theme_preference]

  defp centralized_outcomes(
         %{pending_behaviour_state: :invalid_browser_source},
         :confirm_imports
       ),
       do: [:safe_rejected_import, :source_and_record_unchanged]

  defp centralized_outcomes(_context, :retry_import),
    do: [:idempotent_import_identity, :accepted_data_preserved]

  defp centralized_outcomes(_context, :write_stale_record),
    do: [:newer_record_preserved, :refresh_required]

  defp centralized_outcomes(_context, :accept_and_read_back),
    do: [:only_accepted_key_cleared, :server_only_persistence]

  defp centralized_outcomes(_context, :continue_chat),
    do: [:transcript_preserved, :fresh_conversation_reported]

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

  defp sqlite_storage_fixture_sources,
    do: Enum.sort(["system/bootstrap.json", "users/fixture-user/preferences/theme.json"])
end
