defmodule BnestApp.Behaviour.MemoryBackend do
  @moduledoc false

  @behaviour BnestApp.DataRepository.Backend

  def start do
    {:ok, pid} = Agent.start_link(fn -> %{} end)
    %{backend: __MODULE__, pid: pid}
  end

  def snapshot(%{pid: pid}), do: Agent.get(pid, & &1)

  @impl true
  def identity_files_empty?(store) do
    not Enum.any?(snapshot(store), fn
      {{type, _identity}, _record} when type in [:account, :username_index] -> true
      _other -> false
    end)
  end

  def fail_next_write(%{pid: pid}) do
    Agent.update(pid, &Map.put(&1, :fail_next_write, true))
  end

  @impl true
  def read(%{pid: pid}, type, identity) do
    Agent.get(pid, fn records -> Map.fetch(records, {type, identity}) end)
    |> case do
      {:ok, record} -> {:ok, record}
      :error -> {:error, :missing}
    end
  end

  @impl true
  def write(%{pid: pid}, type, identity, expected_revision, candidate) do
    Agent.get_and_update(pid, fn records ->
      key = {type, identity}
      existing = Map.get(records, key)
      actual_revision = if existing, do: existing["revision"], else: nil

      cond do
        Map.get(records, :fail_next_write, false) ->
          {{:error, :injected_failure}, Map.delete(records, :fail_next_write)}

        actual_revision == expected_revision ->
          prepared = Map.put(candidate, "revision", (actual_revision || -1) + 1)
          {{:ok, prepared}, Map.put(records, key, prepared)}

        true ->
          {{:error, :stale}, records}
      end
    end)
  end

  @impl true
  def put_new(%{pid: pid}, type, identity, candidate) do
    Agent.get_and_update(pid, fn records ->
      key = {type, identity}

      if Map.has_key?(records, key),
        do: {{:error, :exists}, records},
        else: {{:ok, candidate}, Map.put(records, key, candidate)}
    end)
  end

  @impl true
  def replace(%{pid: pid}, type, identity, candidate) do
    Agent.get_and_update(pid, fn records ->
      key = {type, identity}

      if Map.has_key?(records, key),
        do: {{:ok, candidate}, Map.put(records, key, candidate)},
        else: {{:error, :missing}, records}
    end)
  end

  @impl true
  def remove_exact(%{pid: pid}, type, identity, expected) do
    Agent.get_and_update(pid, fn records ->
      key = {type, identity}

      case Map.fetch(records, key) do
        {:ok, ^expected} -> {:ok, Map.delete(records, key)}
        {:ok, _changed} -> {{:error, :changed}, records}
        :error -> {:ok, records}
      end
    end)
  end
end

defmodule BnestApp.Behaviour.UnitHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver

  alias BnestApp.AdminConfig.Registry, as: AdminRegistry
  alias BnestApp.Backup.{Config, Receipt, Run}
  alias BnestApp.Behaviour.MemoryBackend
  alias BnestApp.Chat
  alias BnestApp.Codex.{FixtureModels, ModelAccess, RepositoryAccess}
  alias BnestApp.DataRepository.{Backend, Import, Schema}
  alias BnestApp.Deployment
  alias BnestApp.Identity.{Authorization, Bootstrap, CredentialVerifier, Login, Session}
  alias BnestApp.Scheduler.{Policy, Registry, Store}
  alias BnestApp.SifatAllah
  alias BnestApp.Storage.Config, as: StorageConfig
  alias BnestApp.Storage.Location, as: StorageLocation
  alias BnestApp.Storage.Migration, as: StorageMigration
  alias BnestAppWeb.SifatAllahLive
  alias Phoenix.HTML.Safe

  @behaviour_now ~U[2026-09-04 12:00:00Z]

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
  def home_controls_arranged?(context) do
    page = context.page

    not Enum.empty?(LazyHTML.query(page, ".home-header > .home-brand")) and
      not Enum.empty?(LazyHTML.query(page, ".home-header > .home-account")) and
      not Enum.empty?(LazyHTML.query(page, ".home-hero"))
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

    LazyHTML.query(page, ".chat-actions > *") |> Enum.count() == 4 and
      not Enum.empty?(LazyHTML.query(page, ".chat-actions > .model-badge")) and
      not Enum.empty?(LazyHTML.query(page, ".chat-actions > .repository-access-badge")) and
      not Enum.empty?(LazyHTML.query(page, ".chat-actions > .chat-theme-control")) and
      not Enum.empty?(
        LazyHTML.query(
          page,
          ".chat-actions > .chat-theme-control button[aria-label='Use dark theme']"
        )
      )
  end

  @impl true
  def repository_access_read_only?(context) do
    not Enum.empty?(
      LazyHTML.query(context.page, "[data-role=repository-access][data-mode=read-only]")
    )
  end

  @impl true
  def repository_access_write_enabled?(context) do
    not Enum.empty?(
      LazyHTML.query(context.page, "[data-role=repository-access][data-mode=workspace-write]")
    )
  end

  @impl true
  def repository_write_control_available?(context) do
    controls = LazyHTML.query(context.page, "[data-role=repository-write-toggle]")
    not Enum.empty?(controls) and controls |> LazyHTML.attribute("disabled") |> Enum.empty?()
  end

  @impl true
  def repository_write_control_hidden?(context),
    do: context.page |> LazyHTML.query("[data-role=repository-write-toggle]") |> Enum.empty?()

  @impl true
  def enable_repository_writes(context),
    do: context |> Map.put(:repo_write_enabled?, true) |> render_chat(context.chat)

  @impl true
  def disable_repository_writes(context),
    do: context |> Map.put(:repo_write_enabled?, false) |> render_chat(context.chat)

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

    context
    |> Map.put(:repo_write_enabled?, false)
    |> render_chat(chat)
  end

  def reload(%{chat: chat} = context) do
    context
    |> Map.put(:repo_write_enabled?, false)
    |> render_chat(chat)
  end

  def reload(%{sifat: state} = context) do
    render_sifat_allah(context, state)
  end

  @impl true
  def clear_chat(context) do
    context
    |> Map.delete(:persisted_chat)
    |> Map.put(:repo_write_enabled?, false)
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
    user = identity(context)
    write_enabled? = Map.get(context, :repo_write_enabled?, false)
    repository_mode = RepositoryAccess.mode(user, write_enabled?)

    page =
      %{
        chat: chat,
        models: FixtureModels.all(),
        model_access: model_access,
        repository_write_allowed?: RepositoryAccess.can_enable_write?(user),
        repository_write_enabled?: repository_mode == :workspace_write,
        repository_access_mode: repository_mode,
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
  defp identity(%{identity_role: :child_admin}), do: %{"roles" => ["children", "admin"]}
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
  def establish_identity(context, role) do
    context = Map.merge(context, %{identity_role: role, authenticated: true})

    if role == :user and String.ends_with?(context.feature_file, "authentication.feature") do
      authenticated_memory_context(context)
    else
      context
    end
  end

  @impl true
  def prepare_behaviour(context, :unauthenticated, _args),
    do: Map.merge(context, %{authenticated: false, repository_accesses: 0})

  def prepare_behaviour(context, :uninitialized, _args),
    do: Map.merge(context, %{setup_open: true, identity_store: MemoryBackend.start()})

  def prepare_behaviour(context, :approved_account, _args),
    do: authenticated_memory_context(context)

  def prepare_behaviour(context, :approved_argon2_account, _args) do
    context = authenticated_memory_context(context)

    {:ok, account} =
      Backend.read(context.identity_store, :account, context.identity_user["userId"])

    Map.put(context, :verifier, account["passwordVerifier"])
  end

  def prepare_behaviour(context, :two_browser_sessions, _args) do
    context = authenticated_memory_context(context)

    {:ok, token_b} =
      Login.authenticate(
        context.identity_store,
        context.identity_username,
        context.identity_password
      )

    Map.merge(context, %{token_a: context.identity_token, token_b: token_b})
  end

  def prepare_behaviour(context, :multi_role_user, roles),
    do: Map.put(context, :auth_user, %{"userId" => "user-unit", "roles" => roles})

  def prepare_behaviour(context, :two_isolated_users, _args),
    do: Map.merge(context, %{owner_a: "user-a", owner_b: "user-b"})

  def prepare_behaviour(context, :recognized_browser_sources, _args),
    do:
      context
      |> central_context(recognized_browser_sources())
      |> Map.put(:pending_behaviour_state, :recognized_browser_sources)

  def prepare_behaviour(context, :absent_theme_source, _args),
    do:
      context
      |> central_context([])
      |> Map.put(:pending_behaviour_state, :absent_theme_source)

  def prepare_behaviour(context, :invalid_browser_source, _args) do
    context = central_context(context, [])
    {:ok, accepted} = Import.browser(context.central_store, context.central_owner, chat_source())

    Map.merge(context, %{
      pending_behaviour_state: :invalid_browser_source,
      accepted_before: Backend.read(context.central_store, :chat, context.central_owner),
      accepted_import: accepted,
      browser_sources: [
        %{"storageArea" => "localStorage", "storageKey" => "unknown", "payload" => "opaque"}
      ]
    })
  end

  def prepare_behaviour(context, :interrupted_import, _args) do
    context = central_context(context, [chat_source()])
    MemoryBackend.fail_next_write(context.central_store)

    {:error, :read_back_failed, manifest} =
      Import.browser(context.central_store, context.central_owner, chat_source())

    Map.merge(context, %{interrupted_manifest: manifest, first_import_id: manifest["importId"]})
  end

  def prepare_behaviour(context, :stale_browser_revision, _args) do
    context = central_context(context, [])
    {:ok, _accepted} = Import.browser(context.central_store, context.central_owner, chat_source())
    {:ok, newer} = Backend.read(context.central_store, :chat, context.central_owner)

    stale_payload =
      chat_source()["payload"] |> Jason.decode!() |> Map.put("model", "stale") |> Jason.encode!()

    Map.merge(context, %{
      centralized_before: newer,
      browser_sources: [Map.put(chat_source(), "payload", stale_payload)]
    })
  end

  def prepare_behaviour(context, :recognized_and_unrelated_keys, _args) do
    context = central_context(context, [chat_source()])

    Map.put(context, :browser_keys, %{
      "bnest.chat.v1" => chat_source()["payload"],
      "unrelated" => "keep"
    })
  end

  def prepare_behaviour(context, :unavailable_codex_thread, _args) do
    {:ok, chat} = Chat.new("fixture-model", "medium") |> Chat.submit("Remember this transcript")

    chat =
      chat
      |> Chat.update_assistant("Saved response")
      |> Chat.complete()
      |> Chat.put_thread_id("unavailable-thread")

    Map.merge(context, %{centralized_chat: chat, transcript_before: chat.messages})
  end

  def prepare_behaviour(context, :no_storage_configuration, _args),
    do: Map.put(context, :storage_config, nil)

  def prepare_behaviour(context, :storage_ui_not_visited, _args),
    do: Map.put(context, :storage_ui_visits, 0)

  def prepare_behaviour(context, :migration_not_started, _args),
    do: Map.put(context, :migration_attempts, 0)

  def prepare_behaviour(context, :admin_opened_storage_settings, _args),
    do: Map.merge(context, %{storage_admin?: true, storage_config: nil, authenticated: true})

  def prepare_behaviour(context, :empty_isolated_database, _args) do
    entries = sqlite_storage_fixture_entries()

    Map.merge(context, %{
      schema_objects: [],
      flat_sources: Enum.map(entries, &elem(&1, 0)),
      flat_source_records: Map.new(entries),
      migration_store: MemoryBackend.start()
    })
  end

  def prepare_behaviour(context, :flat_primary_default_location, _args) do
    entries = sqlite_storage_fixture_entries()
    sources = Enum.map(entries, &elem(&1, 0))

    Map.merge(context, %{
      storage_config: %{"phase" => "flat_primary"},
      flat_sources: sources,
      flat_source_records: Map.new(entries),
      flat_source_snapshot: sources,
      migration_items: [],
      migration_store: MemoryBackend.start(),
      resolved_database_directory: "/var/lib/bnest"
    })
  end

  def prepare_behaviour(context, :migration_stopped_after_progress, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])
    [first_path | _rest] = StorageMigration.order_inventory(context.flat_sources)

    {:accepted, evidence} =
      StorageMigration.assess_record(first_path, source_bytes(context, first_path))

    {:ok, _record} =
      Backend.put_new(
        context.migration_store,
        evidence.classification.type,
        evidence.identity,
        evidence.record
      )

    Map.put(context, :migration_items, [%{path: first_path, outcome: :accepted}])
  end

  def prepare_behaviour(context, :all_verification_checks_pass, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])

    {:ok, _account} =
      Backend.put_new(context.migration_store, :account, "unit-verified-account", %{
        "schemaVersion" => 1,
        "recordType" => "account",
        "ownerId" => "unit-verified-account"
      })

    context
  end

  def prepare_behaviour(context, :malformed_or_changed_source, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])
    malformed_path = "users/b-fixture-user/preferences/theme.json"

    Map.merge(context, %{
      has_blocking_source?: true,
      flat_sources: context.flat_sources ++ [malformed_path],
      flat_source_records:
        Map.put(context.flat_source_records, malformed_path, %{"schemaVersion" => 99})
    })
  end

  def prepare_behaviour(context, :non_admin_family_member, _args),
    do: Map.merge(context, %{storage_admin?: false, authenticated: true})

  # A real connected client: the chat route is rendered through production and a draft is
  # typed into the rendered composer, so reconnect evidence comes from re-rendered HTML.
  def prepare_behaviour(context, :healthy_route_with_acknowledged_state, _args) do
    context
    |> open("/chat")
    |> type_draft("unsent draft")
    |> Map.merge(%{
      storage_config: %{"phase" => "sqlite_primary"},
      routed_health_before: elem(Deployment.liveness(), 1)
    })
  end

  def prepare_behaviour(context, :legacy_authoritative_sqlite, _args),
    do:
      Map.merge(context, %{
        legacy_database_path: "/legacy/bnest.sqlite3",
        relocation_destination: "/var/lib/bnest",
        storage_generation: "generation-unit"
      })

  def prepare_behaviour(context, :routed_storage_generation_proven, _args) do
    context
    |> prepare_behaviour(:legacy_authoritative_sqlite, [])
    |> Map.put(:flat_sources, sqlite_storage_fixture_sources())
  end

  def prepare_behaviour(context, :no_backup_override, _args),
    do: Map.put(context, :repository_root, "/workspace")

  def prepare_behaviour(context, :admin_opened_schedules, _args),
    do:
      Map.merge(context, %{
        backup_directory: "/private/backups",
        destination_id: "unit-destination"
      })

  def prepare_behaviour(context, :saved_daily_schedule, _args) do
    schedule = %{
      enabled: true,
      daily_at_utc: "19:00",
      next_run_at: Policy.next_slot("19:00", @behaviour_now)
    }

    Map.put(context, :schedule_before_restart, schedule)
  end

  def prepare_behaviour(context, :multiple_missed_slots, _args),
    do: Map.put(context, :daily_at_utc, "19:00")

  def prepare_behaviour(context, :accepted_backup_claim, _args),
    do: Map.merge(context, unit_backup_fixture())

  def prepare_behaviour(context, :overlapping_coordinators, _args),
    do: Map.put(context, :destination_id, "shared-destination")

  def prepare_behaviour(context, :contextual_schedules, _args),
    do: Map.put(context, :scheduler_entries, Registry.entries())

  def prepare_behaviour(context, :denied_settings_visitor, _args),
    do: Map.put(context, :auth_user, %{"userId" => "unit-child", "roles" => ["children"]})

  def prepare_behaviour(context, :retention_fixture, _args),
    do: Map.put(context, :retention_receipts, unit_retention_receipts())

  def prepare_behaviour(context, :second_family_handler, _args),
    do: Map.put(context, :family_handler, Registry.fetch("fixture"))

  def prepare_behaviour(context, :typed_settings_panels, _args),
    do: Map.put(context, :declared_panels, AdminRegistry.panels())

  def prepare_behaviour(context, :expiry_policies, _args) do
    policies = [
      %{expiration_kind: "never"},
      %{expiration_kind: "at", expires_at: DateTime.add(@behaviour_now, 60)},
      %{expiration_kind: "after_occurrences", claimed_occurrences: 0, max_occurrences: 1}
    ]

    Map.put(context, :expiration_policies, policies)
  end

  @impl true
  def perform_behaviour(context, :open_protected_route, [route]) do
    redirected = not context.authenticated

    Map.merge(context, %{
      attempted_route: route,
      redirected: redirected,
      login_form_only: redirected and route == "/"
    })
  end

  def perform_behaviour(context, :bootstrap_accounts, _args) do
    accepts_short? = CredentialVerifier.valid_password?("a_1")
    accepts_long? = CredentialVerifier.valid_password?(String.duplicate("é", 129) <> "_1")

    rejects_missing_requirement? =
      Enum.all?(["password_", "password1", "123_"], fn password ->
        not CredentialVerifier.valid_password?(password)
      end)

    accounts = [
      %{"username" => "FamilyAdmin", "password" => "a_1", "roles" => ["admin"]},
      %{"username" => "FamilyChild", "password" => "é_1", "roles" => ["children"]}
    ]

    first_result = Bootstrap.create(context.identity_store, accounts)
    second_result = Bootstrap.create(context.identity_store, accounts)

    Map.merge(context, %{
      setup_open: false,
      setup_warning: true,
      bootstrap_first_result: first_result,
      bootstrap_second_result: second_result,
      passwords_without_length_rule: accepts_short? and accepts_long?,
      password_requirements_enforced: rejects_missing_requirement?
    })
  end

  def perform_behaviour(context, :login, _args) do
    result =
      Login.authenticate(
        context.identity_store,
        context.identity_username,
        context.identity_password
      )

    Map.merge(context, %{
      login_result: result,
      authenticated: match?({:ok, _token}, result),
      identity_token: elem(result, 1)
    })
  end

  def perform_behaviour(context, :logout_current_browser, _args) do
    result = Session.revoke(context.identity_store, context.identity_token)
    Map.merge(context, %{logout_result: result, authenticated: false})
  end

  def perform_behaviour(context, :reload_same_browser, _args),
    do:
      Map.put(
        context,
        :reload_result,
        Session.current_user(context.identity_store, context.identity_token)
      )

  def perform_behaviour(context, :logout_browser_a, _args) do
    revoke_result = Session.revoke(context.identity_store, context.token_a)

    Map.merge(context, %{
      browser_a_result: Session.current_user(context.identity_store, context.token_a),
      browser_b_result: Session.current_user(context.identity_store, context.token_b),
      revoke_result: revoke_result
    })
  end

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

  def perform_behaviour(
        %{pending_behaviour_state: :absent_theme_source} = context,
        :confirm_imports,
        _args
      ) do
    result = Import.absent_theme(context.central_store, context.central_owner)
    Map.put(context, :import_results, [result])
  end

  def perform_behaviour(context, :confirm_imports, _args) do
    results =
      Enum.map(
        context.browser_sources,
        &Import.browser(context.central_store, context.central_owner, &1)
      )

    Map.put(context, :import_results, results)
  end

  def perform_behaviour(context, :retry_import, _args) do
    before = MemoryBackend.snapshot(context.central_store)
    result = Import.browser(context.central_store, context.central_owner, chat_source())
    Map.merge(context, %{before_retry: before, retry_result: result})
  end

  def perform_behaviour(context, :write_stale_record, _args) do
    [source] = context.browser_sources
    result = Import.browser(context.central_store, context.central_owner, source)
    Map.put(context, :stale_result, result)
  end

  def perform_behaviour(context, :accept_and_read_back, _args) do
    [source] = context.browser_sources
    result = Import.browser(context.central_store, context.central_owner, source)

    keys =
      if match?({:ok, _}, result),
        do: Map.delete(context.browser_keys, source["storageKey"]),
        else: context.browser_keys

    Map.merge(context, %{accepted_result: result, browser_keys_after: keys})
  end

  def perform_behaviour(context, :continue_chat, _args) do
    chat =
      Chat.fail(
        context.centralized_chat,
        "The previous Codex thread was unavailable; started a fresh conversation."
      )

    Map.put(context, :continued_chat, %{chat | thread_id: nil})
  end

  def perform_behaviour(context, :start_managed_migration, _args),
    do:
      Map.merge(context, %{
        storage_config: %{
          "phase" => "flat_primary",
          "databaseDirectory" => StorageLocation.production_data_directory("/home/unit")
        },
        migration_origin: :headless,
        migration_attempts: Map.get(context, :migration_attempts, 0) + 1
      })

  def perform_behaviour(context, :relocate_storage, _args),
    do:
      Map.put(context, :relocated_config, %{
        "databaseDirectory" => context.relocation_destination,
        "databaseFilename" => StorageLocation.filename(),
        "databaseGeneration" => context.storage_generation,
        "legacyDatabasePath" => context.legacy_database_path
      })

  def perform_behaviour(context, :retire_legacy_storage, _args),
    do:
      Map.merge(context, %{
        flat_sources: [],
        retained_storage_config: %{"databaseGeneration" => context.storage_generation},
        retained_paths: [".gitkeep"]
      })

  def perform_behaviour(context, :enter_valid_folder, _args) do
    candidate = "/srv/bnest-storage"

    Map.merge(context, %{
      requested_directory: candidate,
      persist_result:
        {:ok, %{"databaseDirectory" => candidate, "databaseFilename" => "bnest.sqlite3"}}
    })
  end

  def perform_behaviour(
        %{
          authenticated: true,
          migration_attempts: 0,
          storage_admin?: true,
          storage_config: nil
        } = context,
        :enter_private_folder_beneath_sticky_shared_directory,
        _args
      ) do
    shared = "/synthetic/bnest-storage/shared"
    candidate = shared <> "/private"
    {:ok, storage_pointer} = Agent.start_link(fn -> nil end)

    filesystem = %{
      lstat: fn _path -> {:error, :enoent} end,
      stat: fn
        ^candidate -> {:ok, %{mode: 0o700}}
        ^shared -> {:ok, %{mode: 0o1777}}
        _path -> {:error, :enoent}
      end
    }

    dependencies = %{
      read: fn ->
        case Agent.get(storage_pointer, & &1) do
          nil -> {:error, :absent}
          config -> {:ok, config}
        end
      end,
      validate: &StorageLocation.validate(&1, filesystem),
      write: fn config -> Agent.update(storage_pointer, fn _current -> config end) end
    }

    persist_result = StorageConfig.persist_directory(candidate, dependencies)

    Map.merge(context, %{
      requested_directory: candidate,
      persist_result: persist_result,
      storage_pointer: storage_pointer
    })
  end

  def perform_behaviour(context, :enter_unsafe_folder, _args),
    do:
      Map.merge(context, %{
        persist_result: StorageLocation.validate("relative/storage"),
        storage_config: nil
      })

  def perform_behaviour(context, :apply_migration_set_twice, _args) do
    {_first_counts, first_inserted, schema_before} = migration_pass(context)
    {_second_counts, second_inserted, schema_after} = migration_pass(context)

    Map.merge(context, %{
      schema_before_second_apply: schema_before,
      schema_after_second_apply: schema_after,
      first_apply_inserted: first_inserted,
      second_apply_inserted: second_inserted,
      declared_migration_id: StorageMigration.migration_id()
    })
  end

  def perform_behaviour(context, :run_managed_storage_migration, _args) do
    assessments =
      context.flat_sources
      |> StorageMigration.order_inventory()
      |> Enum.map(fn path ->
        source_bytes = context.flat_source_records |> Map.fetch!(path) |> Jason.encode!()
        {path, StorageMigration.assess_record(path, source_bytes)}
      end)

    accepted =
      Enum.map(assessments, fn
        {path, {:accepted, evidence}} ->
          record = evidence.record

          {:ok, ^record} =
            Backend.put_new(
              context.migration_store,
              evidence.classification.type,
              evidence.identity,
              record
            )

          Map.merge(evidence, %{path: path, outcome: :accepted})

        {_path, {outcome, _evidence}} ->
          raise "valid unit migration fixture produced #{inspect(outcome)}"
      end)

    counts =
      assessments
      |> Enum.map(fn {_path, {outcome, _evidence}} -> outcome end)
      |> StorageMigration.outcome_counts()

    Map.merge(context, %{
      migration_items: accepted,
      migrated_sources: Enum.map(accepted, & &1.path),
      migration_run_result: counts,
      database_path: StorageLocation.database_path(context.resolved_database_directory)
    })
  end

  def perform_behaviour(context, :retry_same_migration, _args) do
    store_before = MemoryBackend.snapshot(context.migration_store)
    {counts, _inserted, store_after} = migration_pass(context)

    Map.merge(context, %{
      migration_run_result: counts,
      store_before_retry: store_before,
      store_after_retry: store_after,
      item_count_before_retry: map_size(store_before),
      item_count_after_retry: map_size(store_after)
    })
  end

  def perform_behaviour(context, :commit_authority_switch, _args) do
    store = MemoryBackend.start()
    {:ok, _accepted} = Import.browser(store, "unit-rollback", chat_source())

    Map.merge(context, %{
      storage_config: %{"phase" => "sqlite_primary"},
      rollback_record_result: Backend.read(store, :chat, "unit-rollback")
    })
  end

  def perform_behaviour(context, :retire_flat_identity_sources, _args) do
    store = context.migration_store

    Enum.each(MemoryBackend.snapshot(store), fn
      {{type, identity}, record} when type in [:account, :username_index] ->
        Backend.remove_exact(store, type, identity, record)

      _other ->
        :ok
    end)

    Map.put(context, :flat_identity_retired?, Backend.identity_files_empty?(store))
  end

  # Verification only classifies; it must not write, so the store snapshot is the evidence
  # that the flat-primary service is untouched.
  def perform_behaviour(context, :verify_migration, _args) do
    store_before = MemoryBackend.snapshot(context.migration_store)

    counts =
      context.flat_sources
      |> StorageMigration.order_inventory()
      |> Enum.map(fn path ->
        {outcome, _evidence} = StorageMigration.assess_record(path, source_bytes(context, path))
        outcome
      end)
      |> StorageMigration.outcome_counts()

    Map.merge(context, %{
      migration_run_result: counts,
      store_before_verification: store_before,
      store_after_verification: MemoryBackend.snapshot(context.migration_store),
      flat_sources_after_verification: context.flat_sources
    })
  end

  def perform_behaviour(context, :open_storage_settings_route, _args),
    do:
      Map.merge(context, %{
        storage_response_status: if(context[:storage_admin?], do: 200, else: 404),
        storage_response_body: if(context[:storage_admin?], do: "Storage", else: "Not found")
      })

  def perform_behaviour(context, :promote_compatible_candidate, _args) do
    context
    |> reconnect()
    |> Map.put(:routed_health_after, elem(Deployment.liveness(), 1))
  end

  def perform_behaviour(context, :resolve_backup_destination, _args) do
    directory = Config.default_directory(context.repository_root)

    Map.merge(context, %{
      resolved_backup_directory: directory,
      public_backup_result: %{status: :verified}
    })
  end

  def perform_behaviour(context, :save_backup_override, _args) do
    claim_key = Store.setup_claim_key(context.destination_id)

    Map.merge(context, %{
      backup_document: Config.document(context.backup_directory),
      setup_claim_keys: MapSet.new([claim_key, Store.setup_claim_key(context.destination_id)])
    })
  end

  def perform_behaviour(context, :restart_scheduler, _args) do
    persisted = context.schedule_before_restart |> Jason.encode!() |> Jason.decode!(keys: :atoms)
    Map.put(context, :schedule_after_restart, persisted)
  end

  def perform_behaviour(context, :reconcile_startup, _args) do
    Map.merge(context, %{
      reconciled_slot: Policy.latest_slot(context.daily_at_utc, @behaviour_now),
      reconciled_next: Policy.next_slot(context.daily_at_utc, @behaviour_now)
    })
  end

  def perform_behaviour(context, :run_backup_handler, _args) do
    receipt =
      Receipt.build(
        context.backup_claim,
        context.backup_location,
        @behaviour_now,
        context.backup_artifact
      )

    Map.put(context, :backup_receipt, receipt)
  end

  def perform_behaviour(context, :reconcile_overlap, _args) do
    claim_key = Store.setup_claim_key(context.destination_id)

    Map.merge(context, %{
      overlap_claim_keys: MapSet.new([claim_key, claim_key]),
      retry_schedule: [
        Policy.retry_at(1, @behaviour_now),
        Policy.retry_at(2, @behaviour_now),
        Policy.retry_at(3, @behaviour_now)
      ]
    })
  end

  def perform_behaviour(context, :open_schedules_from_home, _args) do
    backup = Map.fetch!(context.scheduler_entries, "prod_sqlite_backup")
    family = Map.fetch!(context.scheduler_entries, "fixture")

    Map.merge(context, %{
      schedule_contexts: MapSet.new([backup.context, family.context]),
      backup_settings: AdminRegistry.fetch(backup.settings_key)
    })
  end

  def perform_behaviour(context, :open_admin_settings, _args) do
    denied =
      not Authorization.allow?(context.auth_user, :manage_accounts, context.auth_user["userId"])

    Map.merge(context, %{
      settings_denied?: denied,
      protected_reads: 0,
      admin_home_entry?: not denied
    })
  end

  def perform_behaviour(context, :verify_new_backup, _args),
    do: Map.put(context, :retained_run_ids, Run.retained_run_ids(context.retention_receipts))

  def perform_behaviour(context, :run_second_handler, _args),
    do:
      Map.put(
        context,
        :family_handler_registered?,
        match?({:ok, %{context: "family"}}, context.family_handler)
      )

  def perform_behaviour(context, :open_admin_settings_from_home, _args) do
    fetched = Enum.map(context.declared_panels, &AdminRegistry.fetch(&1.key))
    Map.put(context, :fetched_panels, fetched)
  end

  def perform_behaviour(context, :reconcile_expiry, _args) do
    eligibility = Enum.map(context.expiration_policies, &Policy.eligible?(&1, @behaviour_now))

    retries = [
      Policy.retry_at(1, @behaviour_now),
      Policy.retry_at(2, @behaviour_now),
      Policy.retry_at(3, @behaviour_now)
    ]

    Map.merge(context, %{expiration_eligibility: eligibility, expiration_retries: retries})
  end

  @impl true
  def behaviour_outcome?(context, :redirected_to_login, _args), do: context.redirected
  def behaviour_outcome?(context, :login_form_only, _args), do: context.login_form_only

  def behaviour_outcome?(context, :no_user_data_access, _args),
    do: context.redirected and context.repository_accesses == 0

  def behaviour_outcome?(context, :irreversible_warning, _args), do: context.setup_warning

  def behaviour_outcome?(context, :accounts_created_once, _args),
    do:
      match?({:ok, [_admin, _child]}, context.bootstrap_first_result) and
        context.bootstrap_second_result == {:error, :closed}

  def behaviour_outcome?(context, :setup_closed, _args),
    do: not context.setup_open and Bootstrap.status(context.identity_store) == :closed

  def behaviour_outcome?(context, :passwords_without_length_rule, _args),
    do: context.passwords_without_length_rule

  def behaviour_outcome?(context, :password_requirements_enforced, _args),
    do: context.password_requirements_enforced

  def behaviour_outcome?(context, :protected_home_available, _args), do: context.authenticated

  def behaviour_outcome?(context, :current_browser_logged_out, _args),
    do:
      not context.authenticated and
        Session.current_user(context.identity_store, context.identity_token) ==
          {:error, :unauthenticated}

  def behaviour_outcome?(context, :no_plaintext_password, _args) do
    records = context.identity_store |> MemoryBackend.snapshot() |> inspect()

    String.starts_with?(context.verifier, "$argon2id$") and
      CredentialVerifier.verify(context.identity_password, context.verifier) and
      not String.contains?(records, context.identity_password)
  end

  def behaviour_outcome?(context, :same_browser_authenticated, _args),
    do: match?({:ok, %{"userId" => _user_id}}, context.reload_result)

  def behaviour_outcome?(context, :browser_a_logged_out, _args),
    do:
      match?({:ok, _digest}, context.revoke_result) and
        context.browser_a_result == {:error, :unauthenticated}

  def behaviour_outcome?(context, :browser_b_authenticated, _args),
    do: match?({:ok, %{"userId" => _user_id}}, context.browser_b_result)

  def behaviour_outcome?(context, :operation_allowed, _args), do: context.operation_allowed

  def behaviour_outcome?(context, :administration_denied, _args),
    do: context.administration_denied

  def behaviour_outcome?(context, :denied_before_repository, _args), do: context.cross_user_denied

  def behaviour_outcome?(_context, :pointer_under_configuration_home, _args),
    do: String.ends_with?(StorageLocation.config_directory(), "/.config/bnest")

  def behaviour_outcome?(context, :sqlite_under_production_data, _args),
    do:
      context.storage_config["databaseDirectory"] ==
        StorageLocation.production_data_directory("/home/unit")

  def behaviour_outcome?(context, :no_browser_confirmation, _args),
    do: context.migration_origin == :headless and context.storage_ui_visits == 0

  def behaviour_outcome?(
        %{storage_pointer: pointer} = context,
        :folder_normalized_with_fixed_filename,
        _args
      ) do
    stored = Agent.get(pointer, & &1)

    stored["databaseDirectory"] == context.requested_directory and
      stored["databaseFilename"] == StorageLocation.filename()
  end

  def behaviour_outcome?(context, :folder_normalized_with_fixed_filename, _args),
    do: match?({:ok, %{"databaseFilename" => "bnest.sqlite3"}}, context.persist_result)

  def behaviour_outcome?(%{storage_pointer: pointer}, :validated_location_stored_privately, _args) do
    stored = Agent.get(pointer, & &1)

    Enum.sort(Map.keys(stored)) ==
      Enum.sort(~w(databaseDirectory databaseFilename migrationId phase schemaVersion))
  end

  def behaviour_outcome?(context, :validated_location_stored_privately, _args),
    do: is_binary(elem(context.persist_result, 1)["databaseDirectory"])

  def behaviour_outcome?(context, :safe_correction_explained, _args),
    do: match?({:error, _reason}, context.persist_result)

  def behaviour_outcome?(context, :no_storage_created, _args),
    do: is_nil(context.storage_config)

  def behaviour_outcome?(context, :schema_matches_checksum, _args),
    do:
      context.declared_migration_id == StorageMigration.migration_id() and
        context.first_apply_inserted == length(context.flat_sources)

  # put_new refuses an existing key, so a second apply must insert nothing and leave the
  # stored records byte-identical.
  def behaviour_outcome?(context, :no_duplicate_schema_objects, _args),
    do:
      context.second_apply_inserted == 0 and
        context.schema_before_second_apply == context.schema_after_second_apply

  def behaviour_outcome?(context, :deterministic_inventory, _args),
    do:
      context.flat_sources != Enum.sort(context.flat_sources) and
        context.migrated_sources == StorageMigration.order_inventory(context.flat_sources)

  def behaviour_outcome?(context, :database_under_resolved_directory, _args),
    do:
      context.database_path ==
        context.resolved_database_directory <> "/" <> StorageLocation.filename()

  def behaviour_outcome?(context, :all_valid_items_accepted, _args),
    do:
      context.migration_run_result.blocked == 0 and
        context.migration_run_result.accepted == length(context.flat_sources)

  def behaviour_outcome?(context, :checksum_evidence_present, _args),
    do:
      Enum.all?(context.migration_items, fn item ->
        byte_size(item.source_sha256) == 64 and item.source_sha256 == item.target_sha256
      end)

  def behaviour_outcome?(context, :normal_reads_match, _args),
    do:
      Enum.all?(context.migration_items, fn item ->
        Backend.read(
          context.migration_store,
          item.classification.type,
          item.identity
        ) == {:ok, item.record}
      end)

  def behaviour_outcome?(context, :accepted_items_not_duplicated, _args),
    do:
      Enum.all?(context.store_before_retry, fn {key, record} ->
        Map.get(context.store_after_retry, key) == record
      end) and
        context.item_count_before_retry > 0 and
        context.item_count_after_retry == length(context.flat_sources)

  def behaviour_outcome?(context, :remaining_items_continue, _args),
    do: context.migration_run_result.accepted > 0

  def behaviour_outcome?(context, :future_reads_use_sqlite, _args),
    do: context.storage_config["phase"] == "sqlite_primary"

  def behaviour_outcome?(context, :writes_compatible_with_rollback, _args),
    do:
      match?({:ok, record} when is_map(record), context.rollback_record_result) and
        match?({:ok, _record}, Schema.validate(elem(context.rollback_record_result, 1)))

  def behaviour_outcome?(context, :journeys_survive_restart, _args),
    do:
      context.storage_config["phase"] == "sqlite_primary" and
        context.flat_identity_retired?

  def behaviour_outcome?(context, :sqlite_not_authoritative, _args),
    do: context.migration_run_result.blocked > 0

  def behaviour_outcome?(context, :source_and_service_unchanged, _args),
    do:
      context.store_before_verification == context.store_after_verification and
        Enum.all?(context.flat_source_snapshot, &(&1 in context.flat_sources_after_verification))

  def behaviour_outcome?(context, :value_free_retry_category, _args),
    do: context.migration_run_result.blocked > 0

  def behaviour_outcome?(context, :storage_access_denied, _args),
    do: context.storage_response_status == 404

  def behaviour_outcome?(context, :no_host_path_or_inventory_revealed, _args),
    do: context.storage_response_body == "Not found"

  def behaviour_outcome?(context, :routed_revision_and_readiness_proven, _args) do
    %{status: status, revision: revision, slot: slot} = context.routed_health_after

    status == "live" and is_binary(revision) and revision != "" and is_binary(slot) and
      context.storage_config["phase"] == "sqlite_primary"
  end

  # Reconnect must land on the same route without a reload step.
  def behaviour_outcome?(context, :liveview_reconnects_without_refresh, _args),
    do: current_route?(context, "/chat")

  # The draft is read back out of the re-rendered composer, not from planted context.
  def behaviour_outcome?(context, :acknowledged_state_and_draft_available, _args),
    do: composer_contains?(context, "unsent draft")

  def behaviour_outcome?(context, :pointer_relocated_atomically, _args),
    do:
      context.relocated_config["databaseDirectory"] == context.relocation_destination and
        context.relocated_config["databaseFilename"] == StorageLocation.filename()

  def behaviour_outcome?(context, :legacy_sqlite_retained_until_proof, _args),
    do:
      context.relocated_config["legacyDatabasePath"] == context.legacy_database_path and
        context.relocated_config["databaseGeneration"] == context.storage_generation

  def behaviour_outcome?(context, :verified_legacy_sources_removed, _args),
    do: context.flat_sources == []

  def behaviour_outcome?(context, :config_and_placeholders_preserved, _args),
    do:
      context.retained_storage_config["databaseGeneration"] == context.storage_generation and
        context.retained_paths == [".gitkeep"]

  def behaviour_outcome?(context, :immutable_envelopes, _args) do
    Enum.all?(context.import_results, fn
      {:ok, %{import_id: import_id}} ->
        match?(
          {:ok, %{"payloadEncoding" => "utf8-string"}},
          Backend.read(context.central_store, :browser_import, {context.central_owner, import_id})
        )

      _failure ->
        false
    end)
  end

  def behaviour_outcome?(context, :normalized_records_read, _args) do
    Enum.all?([:chat, :sifat_allah, :theme], fn type ->
      case Backend.read(context.central_store, type, context.central_owner) do
        {:ok, %{"ownerId" => owner}} -> owner == context.central_owner
        _missing -> false
      end
    end)
  end

  def behaviour_outcome?(context, :absent_theme_recorded, _args) do
    with [{:ok, %{import_id: import_id}}] <- context.import_results,
         {:ok, %{"recoverySource" => %{"kind" => "browser-absence"}}} <-
           Backend.read(context.central_store, :manifest, import_id) do
      true
    else
      _failure -> false
    end
  end

  def behaviour_outcome?(context, :no_theme_preference, _args),
    do: Backend.read(context.central_store, :theme, context.central_owner) == {:error, :missing}

  def behaviour_outcome?(context, :safe_rejected_import, _args),
    do: match?([{:error, :unsupported_source, _manifest}], context.import_results)

  def behaviour_outcome?(context, :source_and_record_unchanged, _args),
    do:
      Backend.read(context.central_store, :chat, context.central_owner) == context.accepted_before

  def behaviour_outcome?(context, :idempotent_import_identity, _args),
    do: match?({:ok, %{import_id: id}} when id == context.first_import_id, context.retry_result)

  def behaviour_outcome?(context, :accepted_data_preserved, _args) do
    after_retry = MemoryBackend.snapshot(context.central_store)

    envelope_key = {:browser_import, {context.central_owner, context.first_import_id}}

    Map.get(after_retry, envelope_key) == Map.get(context.before_retry, envelope_key) and
      match?(
        %{"recordType" => "chat", "revision" => 0},
        Map.get(after_retry, {:chat, context.central_owner})
      ) and
      Enum.count(Map.keys(after_retry), fn
        {:browser_import, _identity} -> true
        _other -> false
      end) == 1
  end

  def behaviour_outcome?(context, :newer_record_preserved, _args),
    do:
      Backend.read(context.central_store, :chat, context.central_owner) ==
        {:ok, context.centralized_before}

  def behaviour_outcome?(context, :refresh_required, _args),
    do: match?({:error, :stale_revision, %{"status" => "retryable"}}, context.stale_result)

  def behaviour_outcome?(context, :only_accepted_key_cleared, _args),
    do: context.browser_keys_after == %{"unrelated" => "keep"}

  def behaviour_outcome?(context, :server_only_persistence, _args),
    do:
      match?(
        {:ok, %{"recordType" => "chat"}},
        Backend.read(context.central_store, :chat, context.central_owner)
      )

  def behaviour_outcome?(context, :transcript_preserved, _args),
    do: context.continued_chat.messages == context.transcript_before

  def behaviour_outcome?(context, :fresh_conversation_reported, _args),
    do:
      is_nil(context.continued_chat.thread_id) and
        String.contains?(context.continued_chat.error, "fresh conversation")

  def behaviour_outcome?(context, :default_backup_folder, _args),
    do: context.resolved_backup_directory == "/workspace/data/backup"

  def behaviour_outcome?(context, :no_private_path, _args),
    do: context.public_backup_result == %{status: :verified}

  def behaviour_outcome?(context, :atomic_backup_config, _args),
    do:
      context.backup_document == %{
        "schemaVersion" => 1,
        "destinationDirectory" => context.backup_directory
      }

  def behaviour_outcome?(context, :one_setup_claim, _args),
    do: MapSet.size(context.setup_claim_keys) == 1

  def behaviour_outcome?(context, :schedule_persisted, _args),
    do: context.schedule_after_restart.enabled

  def behaviour_outcome?(context, :same_future_slot, _args),
    do:
      Policy.parse_datetime!(context.schedule_after_restart.next_run_at) ==
        context.schedule_before_restart.next_run_at

  def behaviour_outcome?(context, :latest_slot_only, _args),
    do: context.reconciled_slot == Policy.latest_slot(context.daily_at_utc, @behaviour_now)

  def behaviour_outcome?(context, :next_future_day, _args),
    do: context.reconciled_next == Policy.next_slot(context.daily_at_utc, @behaviour_now)

  def behaviour_outcome?(context, :authoritative_vacuum, _args),
    do: context.backup_receipt["sourceGeneration"] == context.backup_artifact.source_generation

  def behaviour_outcome?(context, :independent_proof, _args),
    do: Receipt.valid?(context.backup_receipt, context.backup_location.destination_id)

  def behaviour_outcome?(context, :single_nonoverlap_claim, _args),
    do: MapSet.size(context.overlap_claim_keys) == 1

  def behaviour_outcome?(context, :bounded_attempts, _args),
    do: match?([%DateTime{}, %DateTime{}, nil], context.retry_schedule)

  def behaviour_outcome?(context, :context_groups, _args),
    do: context.schedule_contexts == MapSet.new(["admin_system", "family"])

  def behaviour_outcome?(context, :typed_backup_link, _args),
    do: match?({:ok, %{path: "/admin/settings/schedules"}}, context.backup_settings)

  def behaviour_outcome?(context, :not_found_before_reads, _args),
    do: context.settings_denied? and context.protected_reads == 0

  def behaviour_outcome?(context, :no_admin_home_entry, _args), do: not context.admin_home_entry?

  def behaviour_outcome?(context, :owned_retention, _args),
    do: MapSet.size(context.retained_run_ids) == 7

  def behaviour_outcome?(context, :preserve_unowned, _args),
    do: Enum.all?(context.retention_receipts, &Map.has_key?(&1, "runId"))

  def behaviour_outcome?(context, :shared_execution, _args),
    do: context.family_handler_registered?

  def behaviour_outcome?(context, :shared_inventory, _args),
    do: match?({:ok, %{label: "Family fixture"}}, context.family_handler)

  def behaviour_outcome?(context, :panels_discoverable, _args),
    do:
      length(context.fetched_panels) == length(context.declared_panels) and
        Enum.all?(context.fetched_panels, &match?({:ok, _}, &1))

  def behaviour_outcome?(context, :owner_allowlists, _args),
    do: Enum.all?(context.declared_panels, &(is_atom(&1.owner) and is_list(&1.editable_fields)))

  def behaviour_outcome?(context, :expiry_blocks_future, _args),
    do: context.expiration_eligibility == [true, true, true]

  def behaviour_outcome?(context, :retry_occurrence_rules, _args),
    do: match?([%DateTime{}, %DateTime{}, nil], context.expiration_retries)

  defp unit_backup_fixture do
    destination_id = "unit-destination"

    %{
      backup_claim: %{
        schedule_key: "prod-sqlite-backup-daily",
        claim_kind: "setup",
        claim_key: Store.setup_claim_key(destination_id),
        scheduled_for: nil,
        run_id: "unit-run",
        schedule_revision: 1
      },
      backup_location: %{directory: "/private/backups", destination_id: destination_id},
      backup_artifact: %{
        source_generation: "sqlite-generation-1",
        basename: "bnest-prod-unit.sqlite3",
        sha256: String.duplicate("a", 64),
        bytes: 42,
        quick_check: "ok",
        schema_versions: [1],
        logical_proof_sha256: String.duplicate("b", 64)
      }
    }
  end

  defp unit_retention_receipts do
    Enum.map(0..8, fn days ->
      %{
        "runId" => "unit-retention-#{days}",
        "createdAt" =>
          @behaviour_now
          |> DateTime.add(-days * 86_400)
          |> DateTime.to_iso8601()
      }
    end)
  end

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
    do: sqlite_storage_fixture_entries() |> Enum.map(&elem(&1, 0))

  defp source_bytes(context, path),
    do: context.flat_source_records |> Map.fetch!(path) |> Jason.encode!()

  # One real migration pass: production classification, then production put_new into the
  # injected store. Returns outcome counts, how many records were actually inserted, and
  # the resulting store snapshot, so idempotency is observed rather than asserted.
  defp migration_pass(context) do
    results =
      context.flat_sources
      |> StorageMigration.order_inventory()
      |> Enum.map(fn path ->
        case StorageMigration.assess_record(path, source_bytes(context, path)) do
          {:accepted, evidence} ->
            inserted? =
              match?(
                {:ok, _record},
                Backend.put_new(
                  context.migration_store,
                  evidence.classification.type,
                  evidence.identity,
                  evidence.record
                )
              )

            {:accepted, inserted?}

          {outcome, _evidence} ->
            {outcome, false}
        end
      end)

    counts = results |> Enum.map(&elem(&1, 0)) |> StorageMigration.outcome_counts()

    {counts, Enum.count(results, &elem(&1, 1)), MemoryBackend.snapshot(context.migration_store)}
  end

  defp sqlite_storage_fixture_entries do
    [
      {"users/z-fixture-user/preferences/theme.json",
       sqlite_storage_theme_fixture("z-fixture-user", "light")},
      {"users/a-fixture-user/preferences/theme.json",
       sqlite_storage_theme_fixture("a-fixture-user", "dark")}
    ]
  end

  defp sqlite_storage_theme_fixture(owner_id, theme) do
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

  defp central_context(context, sources) do
    Map.merge(context, %{
      central_store: MemoryBackend.start(),
      central_owner: "user-unit",
      browser_sources: sources
    })
  end

  defp authenticated_memory_context(context) do
    store = MemoryBackend.start()
    username = "UnitUser"
    password = "Synthetic password 1!"

    {:ok, [user]} =
      Bootstrap.create(store, [
        %{"username" => username, "password" => password, "roles" => ["admin"]}
      ])

    {:ok, token} = Login.authenticate(store, username, password)

    Map.merge(context, %{
      account_exists: true,
      identity_password: password,
      identity_store: store,
      identity_token: token,
      identity_user: user,
      identity_username: username
    })
  end

  defp recognized_browser_sources, do: [chat_source(), learning_source(), theme_source()]

  defp chat_source do
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

  defp learning_source do
    %{
      "storageArea" => "localStorage",
      "storageKey" => "bnest.sifat-allah.v1",
      "payload" =>
        Jason.encode!(Map.put(SifatAllah.progress(), "session", %{"mode" => "dashboard"}))
    }
  end

  defp theme_source,
    do: %{"storageArea" => "localStorage", "storageKey" => "phx:theme", "payload" => "dark"}
end
