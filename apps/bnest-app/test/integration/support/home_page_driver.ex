defmodule BnestApp.Behaviour.IntegrationHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver
  @endpoint BnestAppWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BnestApp.Backup
  alias BnestApp.Backup.Adapters.ScheduledBackupTask
  alias BnestApp.Backup.Domain.Receipt
  alias BnestApp.Behaviour.IntegrationFamilyChatDriver
  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.Identity.Adapters.{Argon2CredentialHasher, RecordIdentityStore}
  alias BnestApp.Identity.Bootstrap
  alias BnestApp.Identity.Domain.{Authorization, Credentials}
  alias BnestApp.Identity.Ports.IdentityStore
  alias BnestApp.Operations
  alias BnestApp.Preferences
  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.Scheduler
  alias BnestApp.Scheduler.Domain.Policy
  alias BnestApp.Scheduler.Ports.ScheduleStore
  alias BnestApp.SifatAllah
  alias BnestApp.SifatAllah.Domain.Quiz
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Adapters.FileRecordBackend
  alias BnestApp.Storage.Adapters.FlatRetirement
  alias BnestApp.Storage.Adapters.SqliteCoordinator
  alias BnestApp.Storage.Adapters.SqliteMigration
  alias BnestApp.Storage.Adapters.SqliteRelocation
  alias BnestApp.Storage.Domain.Location, as: StorageLocation
  alias BnestApp.Storage.Domain.Normalizer
  alias BnestApp.Storage.Import
  alias BnestApp.Storage.Records
  alias BnestApp.Test.CodexFixtureConversation
  alias BnestApp.Test.CodexFixtureModels, as: FixtureModels
  alias BnestApp.Test.InterruptedChatWriteBackend
  alias BnestApp.Test.SchedulerDispatch
  alias BnestApp.Test.Seeds.Schedules
  alias BnestApp.TestBackupDestination
  alias BnestApp.TestRuntimeRoot

  @behaviour_now ~U[2026-08-30 20:00:00Z]
  @record_operations [:read, :write, :put_new, :replace, :remove_exact]
  @quiz_auto_advance_ms 5_000

  # The statuses the schedules page may show for a schedule without exposing its failure.
  @safe_schedule_status ~r/Enabled|Running|Verified|Never run/u

  # Schedule columns no admin panel lists as an editable field, submitted with a save as a
  # forged form would; `daily_at_utc` is the stored column, the panel's field is
  # `daily_time_wib`.
  @unlisted_schedule_fields %{
    "schedule_key" => "test-user-forged-key",
    "handler_key" => "fixture",
    "schedule_context" => "family",
    "cadence" => "hourly",
    "daily_at_utc" => "00:00",
    "expiration_kind" => "after_occurrences",
    "max_occurrences" => "1"
  }

  # What saving the schedules-backups panel's `enabled` and `daily_time_wib` may change:
  # those two columns and the save's own revision, next run and update time.
  @saved_schedule_columns [:daily_at_utc, :enabled, :next_run_at, :revision, :updated_at]

  @impl true
  def open(%{conn: conn} = context, "/") do
    response = get(conn, "/")
    Map.put(context, :page, LazyHTML.from_fragment(html_response(response, 200)))
  end

  def open(%{conn: conn} = context, "/family-chat") do
    response = get(conn, "/family-chat")
    route = redirected_to(response)
    followed = get(conn, route)

    context
    |> Map.put(:route, route)
    |> Map.put(:page, LazyHTML.from_fragment(followed.resp_body))
  end

  def open(%{conn: conn} = context, "/family-chat/" <> _slug = route) do
    response = get(conn, route)

    context
    |> Map.put(:route, route)
    |> Map.put(:page, LazyHTML.from_fragment(response.resp_body))
  end

  def open(%{conn: conn} = context, route) do
    {:ok, view, _html} = live(conn, route)
    context |> Map.put(:view, view) |> Map.put(:route, route)
  end

  @impl true
  def brand_logo_visible?(%{page: page}) do
    page
    |> LazyHTML.query("[data-role=brand-logo][src='/images/beaver-nest-logo.png']")
    |> Enum.any?()
  end

  def brand_logo_visible?(context) do
    has_element?(context.view, "[data-role=brand-logo][src='/images/beaver-nest-logo.png']")
  end

  # Integration cannot express a browser-only mechanism. Every scenario that needs one is
  # @integration-exempt and proven at FE E2E, so reaching one of these fails instead of
  # giving partial proof.
  @impl true
  def installable_as_app?(_context),
    do:
      raise(
        exempt_message(
          "service-worker installability",
          "A visitor can install Beaver Nest as an app"
        )
      )

  @impl true
  def heading_visible?(%{page: page}, heading) do
    page
    |> LazyHTML.query("h1")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(heading)
  end

  def heading_visible?(context, heading) do
    has_element?(context.view, "h1", heading)
  end

  @impl true
  def text_visible?(context, text) do
    has_element?(context.view, "main", text)
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
  def home_controls_arranged?(_context),
    do:
      raise(
        exempt_message("rendered geometry", "Home controls and content remain visually separated")
      )

  @impl true
  def follow_brand_home_link(context) do
    if has_element?(context.view, "a[aria-label='Beaver Nest home'][href='/']") do
      open(Map.delete(context, :view), "/")
    else
      raise "Beaver Nest home link is not available"
    end
  end

  @impl true
  def data_migration_entry_absent?(context) do
    not Enum.empty?(LazyHTML.query(context.page, "main.home-shell")) and
      context.page |> LazyHTML.query("[data-role=data-migration-entry]") |> Enum.empty?()
  end

  @impl true
  def model_selector_lists_all?(context) do
    Enum.all?(FixtureModels.all(), fn model ->
      has_element?(
        context.view,
        "[data-role=model-selector] option[value='#{model.id}']",
        model.display_name
      )
    end)
  end

  @impl true
  def selected_model?(context, display_name) do
    model = FixtureModels.fetch_by_display_name!(display_name)

    selected_setting?(
      context.view,
      "[data-role=model-selector]",
      "option[value='#{model.id}'][selected]",
      ".model-badge[data-model='#{model.id}']"
    )
  end

  @impl true
  def effort_selector_lists_supported?(context) do
    selected_model_id =
      context.view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role=model-selector] option[selected]")
      |> LazyHTML.attribute("value")
      |> List.first()

    model = FixtureModels.fetch_by_id!(selected_model_id)

    Enum.all?(model.supported_reasoning_efforts, fn effort ->
      has_element?(
        context.view,
        "[data-role=effort-selector] option[value='#{effort}']",
        effort_label(effort)
      )
    end) and
      context.view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role=effort-selector] option")
      |> Enum.count()
      |> Kernel.==(length(model.supported_reasoning_efforts))
  end

  @impl true
  def selected_effort?(context, effort) do
    effort = String.downcase(effort)

    selected_setting?(
      context.view,
      "[data-role=effort-selector]",
      "option[value='#{effort}'][selected]",
      ".model-badge[data-reasoning-effort='#{effort}']"
    )
  end

  @impl true
  def model_selector_available?(context) do
    has_element?(context.view, "[data-role=model-selector]:not([disabled])")
  end

  @impl true
  def model_selector_unavailable?(context) do
    has_element?(context.view, "[data-role=model-selector][disabled]")
  end

  @impl true
  def model_selector_hidden?(context),
    do: not has_element?(context.view, "[data-role=model-selector]")

  @impl true
  def effort_selector_available?(context) do
    has_element?(context.view, "[data-role=effort-selector]:not([disabled])")
  end

  @impl true
  def effort_selector_unavailable?(context) do
    has_element?(context.view, "[data-role=effort-selector][disabled]")
  end

  @impl true
  def effort_selector_hidden?(context),
    do: not has_element?(context.view, "[data-role=effort-selector]")

  @impl true
  def select_model(context, display_name) do
    model = FixtureModels.fetch_by_display_name!(display_name)
    render_change(context.view, "select_model", %{"model" => model.id})
    snapshot = await_push_event(context.view, "persist-chat")
    Map.put(context, :persisted_chat, Jason.encode!(snapshot))
  end

  @impl true
  def select_effort(context, effort) do
    render_change(context.view, "select_effort", %{
      "reasoning_effort" => String.downcase(effort)
    })

    snapshot = await_push_event(context.view, "persist-chat")
    Map.put(context, :persisted_chat, Jason.encode!(snapshot))
  end

  @impl true
  def conversation_empty?(context) do
    not has_element?(context.view, "[data-role=message]")
  end

  @impl true
  def composer_available?(context) do
    has_element?(context.view, "#chat-composer-form textarea[data-role=chat-composer]") and
      not has_element?(context.view, "#chat-composer-form textarea[disabled]") and
      has_element?(context.view, "#chat-composer-form .send-button:not([disabled])")
  end

  @impl true
  def composer_unavailable?(context) do
    has_element?(context.view, "#chat-composer-form textarea[data-role=chat-composer][disabled]") and
      not has_element?(context.view, "#chat-composer-form textarea:not([disabled])") and
      has_element?(context.view, "#chat-composer-form .send-button[disabled]") and
      not has_element?(context.view, "#chat-composer-form .send-button:not([disabled])")
  end

  @impl true
  def clear_chat_control_available?(context) do
    has_element?(context.view, "[data-role=clear-chat]:not([disabled])")
  end

  @impl true
  def chat_controls_arranged?(context) do
    actions =
      context.view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(".chat-actions > *")

    Enum.count(actions) == 4 and
      has_element?(context.view, ".chat-actions > .model-badge") and
      has_element?(context.view, ".chat-actions > .repository-access-badge") and
      has_element?(context.view, ".chat-actions > .chat-theme-control") and
      has_element?(
        context.view,
        ".chat-actions > .chat-theme-control button[aria-label='Use dark theme']"
      )
  end

  @impl true
  def repository_access_read_only?(context) do
    has_element?(context.view, "[data-role=repository-access][data-mode=read-only]")
  end

  @impl true
  def repository_access_write_enabled?(context) do
    has_element?(context.view, "[data-role=repository-access][data-mode=workspace-write]")
  end

  @impl true
  def repository_write_control_available?(context) do
    has_element?(context.view, "[data-role=repository-write-toggle]:not([disabled])")
  end

  @impl true
  def repository_write_control_hidden?(context) do
    not has_element?(context.view, "[data-role=repository-write-toggle]")
  end

  @impl true
  def enable_repository_writes(context) do
    render_click(context.view, "set_repository_write", %{"enabled" => "true"})
    context
  end

  @impl true
  def disable_repository_writes(context) do
    render_click(context.view, "set_repository_write", %{"enabled" => "false"})
    context
  end

  @impl true
  def attempt_empty_message(context), do: submit_composer(context, "   ")

  @impl true
  def send_message(context, message), do: submit_composer(context, message)

  @impl true
  def submit_with_shift_enter(_context, _message),
    do: raise(exempt_message("a keyboard chord", "A visitor sends a message with Shift+Enter"))

  # The composer is disabled while Codex works, so the rendered form is submitted as a forced
  # browser submission would; the LiveView's own busy guard decides what happens.
  @impl true
  def attempt_message_before_finished(context, message) do
    unless composer_unavailable?(context), do: raise("the chat composer is not disabled")

    context.view
    |> element("#chat-composer-form[phx-submit=send]")
    |> render_submit(%{"chat" => %{"prompt" => message}})

    context
  end

  @impl true
  def visitor_message_visible?(context, message) do
    has_element?(context.view, "[data-role=user-message]", message)
  end

  @impl true
  def visitor_message_absent?(context, message) do
    not visitor_message_visible?(context, message)
  end

  @impl true
  def stream_codex_response(context) do
    {prompt, session, context} = unanswered_prompt!(context)

    {events, threads} =
      CodexFixtureConversation.answer(Map.get(context, :codex_threads, %{}), session, prompt)

    context = context |> Map.put(:codex_threads, threads) |> deliver_codex_events(events)
    snapshot = await_push_event(context.view, "persist-chat")

    streamed? =
      context.view
      |> element("[data-role=message]:last-child [data-role=assistant-message]")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-update-count]")
      |> LazyHTML.attribute("data-update-count")
      |> List.first()
      |> then(&(&1 && String.to_integer(&1) >= 2))

    {streamed?, Map.put(context, :persisted_chat, Jason.encode!(snapshot))}
  end

  @impl true
  def in_progress_turn_recovered?(context) do
    page = context.view |> render() |> LazyHTML.from_fragment()

    resumed? =
      page
      |> LazyHTML.query("[data-role=assistant-message][data-streaming=false]")
      |> LazyHTML.attribute("data-update-count")
      |> Enum.any?(&(String.to_integer(&1) >= 2))

    failed_safely? =
      alert_visible?(
        context,
        "The previous response was interrupted. Your transcript is preserved; send a new message to continue."
      )

    visitor_message_count = page |> LazyHTML.query("[data-role=user-message]") |> Enum.count()
    (resumed? or failed_safely?) and visitor_message_count == 1
  end

  @impl true
  def report_public_codex_progress(context) do
    {_prompt, _session, context} = unanswered_prompt!(context)

    context =
      deliver_codex_events(context, [
        {:reasoning_update, "fixture-reasoning", "Fixture reasoning summary"},
        {:assistant_update, "fixture-progress", "Fixture progress"},
        {:assistant_update, "fixture-final", "Fixture final answer"},
        :turn_completed
      ])

    snapshot = await_push_event(context.view, "persist-chat")
    Map.put(context, :persisted_chat, Jason.encode!(snapshot))
  end

  @impl true
  def codex_reasoning_summary_visible?(context) do
    has_element?(context.view, "[data-role=codex-reasoning-summary]", "Fixture reasoning summary")
  end

  @impl true
  def codex_progress_preserved_beside_final_answer?(context) do
    has_element?(context.view, "[data-role=codex-progress-item]", "Fixture progress") and
      has_element?(context.view, "[data-role=assistant-message]", "Fixture final answer")
  end

  @impl true
  def second_codex_response_visible?(context) do
    context.view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-role=assistant-message]")
    |> Enum.count()
    |> Kernel.==(2)
  end

  @impl true
  def one_completed_codex_response_visible?(context) do
    context.view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-role=assistant-message][data-streaming=false]")
    |> Enum.count()
    |> Kernel.==(1)
  end

  # The fixture session refuses this prompt, so what the page shows is the facade's own
  # handling of a session that cannot accept a message.
  @impl true
  def reject_message(context, message), do: submit_composer(context, message)

  @impl true
  def report_codex_error(context, message) do
    {_prompt, _session, context} = unanswered_prompt!(context)
    deliver_codex_events(context, [{:error, message}])
  end

  @impl true
  def alert_visible?(context, message) do
    has_element?(context.view, "[role=alert]", message)
  end

  @impl true
  def type_draft(context, draft) do
    render_change(context.view, "recover_draft", %{"chat" => %{"prompt" => draft}})
    Map.put(context, :draft, draft)
  end

  @impl true
  def composer_contains?(context, draft), do: has_element?(context.view, "textarea", draft)

  @impl true
  def current_route?(context, route), do: context.route == route

  # Integration cannot replace the server under a connected client: remounting the unchanged
  # server would simulate the deployment. Every scenario that reconnects after one is
  # @integration-exempt and proven at FE E2E, so reaching this fails instead of passing.
  @impl true
  def reconnect(_context) do
    raise "integration cannot reconnect after a deployment; " <>
            "the scenario is @integration-exempt (FE E2E proves it)"
  end

  defp exempt_message(mechanism, scenario) do
    "integration cannot express #{mechanism}; " <>
      "#{scenario} is @integration-exempt (FE E2E proves it)"
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
  def reload(%{conn: conn, persisted_chat: persisted_chat} = context) do
    conn = put_connect_params(conn, %{"chat" => persisted_chat})
    {:ok, view, _html} = live(conn, "/chat")
    Map.put(context, :view, view)
  end

  def reload(%{conn: conn, route: "/chat"} = context) do
    {:ok, view, _html} = live(conn, "/chat")
    Map.put(context, :view, view)
  end

  def reload(%{conn: conn, persisted_sifat_allah: persisted_sifat_allah} = context) do
    conn = put_connect_params(conn, %{"sifat_allah" => persisted_sifat_allah})
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")
    Map.put(context, :view, view)
  end

  @impl true
  def clear_chat(context) do
    context.view
    |> element("[data-role=clear-chat]")
    |> render_click()

    %{} = await_push_event(context.view, "clear-chat-storage")
    Map.delete(context, :persisted_chat)
  end

  @impl true
  def study_mode_available?(context) do
    has_element?(
      context.view,
      "button[phx-click=start-learning]:not([disabled])",
      "Belajar 3 Pasangan"
    )
  end

  @impl true
  def quiz_mode_available?(context),
    do:
      has_element?(context.view, "button[phx-click=start-quiz]:not([disabled])", "Latihan Ujian")

  @impl true
  def start_learning(context) do
    context.view
    |> element("button", "Belajar 3 Pasangan")
    |> render_click()

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  # An authenticated learner's progress lives only on the server, so the precondition is saved
  # there through the SifatAllah facade before the page opens again; the Given fails unless
  # the opened page shows it.
  @impl true
  def remember_every_sifat_pair(context) do
    progress =
      Enum.reduce(Quiz.curriculum(), Quiz.progress(), fn pair, acc ->
        Quiz.remember(acc, pair.id)
      end)

    {:ok, _saved} =
      SifatAllah.save_progress(
        context.user_id,
        Map.put(progress, "session", %{"mode" => "dashboard"}),
        nil
      )

    {:ok, view, _html} = live(context.conn, "/apps/sifat-allah")

    unless has_element?(view, ".sifat-stage", "120 dari 120 soal sudah hafal") do
      raise "the saved Sifat Allah progress was not restored"
    end

    Map.put(context, :view, view)
  end

  @impl true
  def swipe_study_card_left(_context),
    do: raise(exempt_message("a touch swipe", "every swiping scenario"))

  @impl true
  def swipe_study_card_right(_context),
    do: raise(exempt_message("a touch swipe", "every swiping scenario"))

  @impl true
  def return_to_mission(context) do
    context.view
    |> element("button", "← Kembali ke misi")
    |> render_click()

    %{} = await_push_event(context.view, "sifat-history-back")
    render_hook(context.view, "dashboard", %{})

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def browser_back_to_mission(_context),
    do:
      raise(
        exempt_message(
          "browser history",
          "Browser Back returns a child from a quiz to the mission"
        )
      )

  @impl true
  def study_card_shows?(context, name, meaning) do
    has_element?(context.view, "[data-role=study-card]", name) and
      has_element?(context.view, "[data-role=study-card]", meaning)
  end

  # The card's colours come from the stylesheet's `.sifat-wajib-side` (green) and
  # `.sifat-mustahil-side` (orange) rules, so each side must carry its own colour class. The
  # computed colours are read at E2E.
  @impl true
  def study_card_colors_attributes?(context) do
    has_element?(
      context.view,
      "[data-role=study-card] .sifat-wajib-side > span",
      ~r/^SIFAT WAJIB$/
    ) and
      has_element?(
        context.view,
        "[data-role=study-card] .sifat-mustahil-side > span",
        ~r/^SIFAT MUSTAHIL$/
      )
  end

  @impl true
  def mark_current_pair_remembered(context) do
    context.view
    |> element("button", "Aku sudah ingat")
    |> render_click()

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def progress_shows?(context, progress) do
    has_element?(context.view, ".sifat-stage", progress)
  end

  @impl true
  def ask_reset_sifat_progress(context) do
    context.view
    |> element("button", "Reset progress")
    |> render_click()

    context
  end

  @impl true
  def confirm_reset_sifat_progress(context) do
    context.view
    |> element("button", "Ya, reset progress")
    |> render_click()

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def start_quiz(context) do
    context.view
    |> element("button", "Latihan Ujian")
    |> render_click()

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def quiz_answer_positions_vary?(context) do
    first_position = answer_position(context.view, "Ada")

    context.view
    |> element("button", "Soal berikutnya →")
    |> render_click()

    _snapshot = await_push_event(context.view, "persist-sifat-allah")
    second_position = answer_position(context.view, "Hudus")

    is_integer(first_position) and is_integer(second_position) and
      first_position != second_position
  end

  @impl true
  def quiz_answer_choices_locked?(context),
    do:
      has_element?(context.view, ".sifat-answer-grid button[disabled]") and
        not has_element?(context.view, ".sifat-answer-grid button:not([disabled])")

  # The LiveView's own five-second timer moves the quiz on, so nothing is sent to the view.
  # The answered question must still be shown just before the five seconds end, and must
  # change soon after, observed by re-rendering for a bounded time.
  @impl true
  def wait_for_quiz_auto_advance(context) do
    question = rendered_quiz_question(context.view)

    if question == nil do
      raise "no quiz question is shown"
    end

    Process.sleep(@quiz_auto_advance_ms - 500)

    if rendered_quiz_question(context.view) != question do
      raise "the quiz moved on before five seconds passed"
    end

    await_quiz_question_change(context.view, question, 50)

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  defp await_quiz_question_change(view, question, attempts) do
    cond do
      rendered_quiz_question(view) != question ->
        :ok

      attempts > 0 ->
        Process.sleep(50)
        await_quiz_question_change(view, question, attempts - 1)

      true ->
        raise "the quiz stayed on #{inspect(question)} after five seconds passed"
    end
  end

  defp rendered_quiz_question(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-role=quiz-question] h2")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
    |> List.first()
  end

  @impl true
  def start_learned_review(context) do
    context.view
    |> element("button[phx-click=start-learned-review]")
    |> render_click()

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def start_focused_review(context) do
    context.view
    |> element("button[phx-click=start-review]")
    |> render_click()

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def swipe_quiz_question_left(_context),
    do: raise(exempt_message("a touch swipe", "every swiping scenario"))

  @impl true
  def swipe_quiz_question_right(_context),
    do: raise(exempt_message("a touch swipe", "every swiping scenario"))

  @impl true
  def next_quiz_question(context) do
    context.view
    |> element("button", "Soal berikutnya →")
    |> render_click()

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def answer_quiz(context, answer) do
    context.view
    |> element("button", answer)
    |> render_click()

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def answer_focused_review(context, answer) do
    context.view
    |> element("button", answer)
    |> render_click()

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def next_focused_review(context) do
    context.view
    |> element("button[phx-click=next-review-question]")
    |> render_click()

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def revision_list_contains?(context, name) do
    has_element?(context.view, "[data-testid=sifat-allah-revision-list]", name)
  end

  @impl true
  def establish_identity(context, role) do
    scenario_key = "#{context.feature_file}:#{context.scenario_name}:#{role}"

    {conn, identity} =
      BnestAppWeb.ConnCase.scenario_authenticated_conn(
        context.conn,
        scenario_key,
        roles_for(role)
      )

    Process.put(:bnest_behaviour_user_id, identity.user_id)
    {:ok, token} = BnestApp.Identity.login(identity.username, identity.password)

    Map.merge(context, %{
      conn: Plug.Test.put_req_cookie(conn, "_bnest_identity", token),
      identity_role: role,
      authenticated: true,
      token: token,
      user_id: identity.user_id,
      identity_username: identity.username
    })
  end

  @impl true
  def prepare_behaviour(context, :unauthenticated, _args),
    do: Map.merge(context, %{authenticated: false, conn: Phoenix.ConnTest.build_conn()})

  def prepare_behaviour(context, :uninitialized, _args) do
    runtime = TestRuntimeRoot.create!("authentication-bootstrap")
    ExUnit.Callbacks.on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)

    Map.merge(context, %{
      identity_store: RecordIdentityStore.new(FileRecordBackend.new!(runtime.path)),
      identity_runtime: runtime
    })
  end

  def prepare_behaviour(context, :approved_account, _args),
    do: Map.put(context, :account_exists, true)

  def prepare_behaviour(context, :approved_argon2_account, _args) do
    {username, password} = BnestAppWeb.ConnCase.test_credentials()
    store = RecordIdentityStore.new(Records.store())
    {:ok, %{"userId" => user_id}} = IdentityStore.read_username(store, username)
    {:ok, account} = IdentityStore.read_account(store, user_id)

    Map.merge(context, %{
      account_exists: true,
      identity_password: password,
      identity_store: store,
      verifier: account["passwordVerifier"]
    })
  end

  def prepare_behaviour(context, :two_browser_sessions, _args) do
    {username, password} = BnestAppWeb.ConnCase.test_credentials()
    {:ok, token_a} = BnestApp.Identity.login(username, password)
    {:ok, token_b} = BnestApp.Identity.login(username, password)
    Map.merge(context, %{token_a: token_a, token_b: token_b})
  end

  def prepare_behaviour(context, :multi_role_user, roles),
    do: Map.put(context, :auth_user, %{"userId" => "user-integration", "roles" => roles})

  def prepare_behaviour(context, :two_isolated_users, _args),
    do: Map.merge(context, %{owner_a: "user-a", owner_b: "user-b"})

  def prepare_behaviour(context, :recognized_browser_sources, _args),
    do:
      Map.merge(context, %{
        central_store: Records.store(),
        browser_sources: recognized_browser_sources()
      })

  def prepare_behaviour(context, :absent_theme_source, _args),
    do:
      Map.merge(context, %{
        central_store: Records.store(),
        browser_sources: [],
        pending_behaviour_state: :absent_theme_source
      })

  def prepare_behaviour(context, :invalid_browser_source, _args) do
    store = Records.store()
    {:ok, accepted} = Import.browser(store, context.user_id, chat_source())

    Map.merge(context, %{
      central_store: store,
      accepted_before: FileRecordBackend.read(store, :chat, context.user_id),
      accepted_import: accepted,
      browser_sources: [
        %{"storageArea" => "localStorage", "storageKey" => "unknown", "payload" => "opaque"}
      ]
    })
  end

  # The import runs against the run-root store through a backend that fails its chat write,
  # as a crash after the envelope is preserved would; the chat record must then be absent.
  def prepare_behaviour(context, :interrupted_import, _args) do
    store = Records.store()

    {:error, :read_back_failed, manifest} =
      Import.browser(InterruptedChatWriteBackend.wrap(store), context.user_id, chat_source())

    {:error, :missing} = FileRecordBackend.read(store, :chat, context.user_id)
    Map.merge(context, %{central_store: store, first_import_id: manifest["importId"]})
  end

  def prepare_behaviour(context, :stale_browser_revision, _args) do
    store = Records.store()
    {:ok, _accepted} = Import.browser(store, context.user_id, chat_source())
    {:ok, newer} = FileRecordBackend.read(store, :chat, context.user_id)

    stale_payload =
      chat_source()["payload"] |> Jason.decode!() |> Map.put("model", "stale") |> Jason.encode!()

    Map.merge(context, %{
      central_store: store,
      centralized_before: newer,
      browser_sources: [Map.put(chat_source(), "payload", stale_payload)]
    })
  end

  def prepare_behaviour(context, :recognized_and_unrelated_keys, _args) do
    Map.merge(context, %{
      central_store: Records.store(),
      browser_storage: [
        chat_source(),
        %{"storageArea" => "localStorage", "storageKey" => "unrelated", "payload" => "keep"}
      ]
    })
  end

  # The saved chat is the precondition, so it is saved through the CodexChat facade into the
  # run-root repository, on the thread the fixture agent session cannot resume.
  def prepare_behaviour(context, :unavailable_codex_thread, _args) do
    {:ok, transcript} =
      Transcript.new("gpt-5.6-terra", "medium") |> Transcript.submit("Remember this transcript")

    transcript =
      transcript
      |> Transcript.update_assistant("Saved response")
      |> Transcript.complete()
      |> Transcript.put_thread_id("unavailable-thread")

    {:ok, _record} = CodexChat.save_transcript(context.user_id, transcript, nil)
    Map.put(context, :transcript_before, transcript.messages)
  end

  def prepare_behaviour(context, :no_backup_override, _args), do: prepare_default_backup(context)

  def prepare_behaviour(context, :admin_opened_schedules, _args),
    do: prepare_backup_destination(context)

  def prepare_behaviour(context, :saved_daily_schedule, _args) do
    ensure_scheduler_storage()
    key = schedule_key("restart")
    :ok = Schedules.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    future_wib = now |> DateTime.add(8 * 60 * 60) |> Calendar.strftime("%H:%M")

    {:ok, _schedule} =
      Scheduler.update_daily(
        key,
        %{"daily_time_wib" => future_wib, "enabled" => "true", "revision" => "1"},
        now
      )

    Map.merge(context, %{schedule_key: key, schedule_before_restart: Scheduler.get_schedule(key)})
  end

  # Seeded three days earlier, due at that day's slot: the scheduler missed that slot and
  # the three after it, up to the latest slot before the scenario's clock.
  def prepare_behaviour(context, :multiple_missed_slots, _args) do
    ensure_scheduler_storage()
    key = schedule_key("catchup")
    seeded_at = DateTime.add(@behaviour_now, -3 * 86_400)
    :ok = Schedules.put_test_schedule(key, "family", "fixture", seeded_at)
    Map.put(context, :schedule_key, key)
  end

  def prepare_behaviour(context, :accepted_backup_claim, _args) do
    ensure_scheduler_storage()
    context = prepare_backup_destination(context)
    key = schedule_key("backup")
    :ok = Schedules.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)
    {:ok, location} = Backup.save_destination(context.backup_directory)
    {:ok, claim} = Scheduler.claim_setup(key, location.destination_id, @behaviour_now)
    Map.merge(context, %{backup_claim: claim, backup_location: location})
  end

  def prepare_behaviour(context, :overlapping_coordinators, _args) do
    ensure_scheduler_storage()
    key = schedule_key("overlap")
    :ok = Schedules.put_test_schedule(key, "family", "fixture", @behaviour_now)
    Map.put(context, :schedule_key, key)
  end

  def prepare_behaviour(context, :contextual_schedules, _args) do
    ensure_scheduler_storage()
    key = schedule_key("family")
    :ok = Schedules.put_test_schedule(key, "family", "fixture", @behaviour_now)

    # The release seeds persisted the admin/system backup schedule.
    Map.merge(context, %{
      schedule_key: key,
      persisted_schedules: %{family: key, admin_system: "prod-sqlite-backup-daily"}
    })
  end

  def prepare_behaviour(context, :retention_fixture, _args) do
    context = prepare_backup_destination(context)
    unknown = Path.join(context.backup_directory, "keep-me.txt")
    File.mkdir_p!(context.backup_directory)
    File.write!(unknown, "synthetic-unowned")
    previous = context.backup_directory <> "-previous"
    File.mkdir_p!(previous)
    File.write!(Path.join(previous, "previous-destination.txt"), "retain")
    Map.merge(context, %{unknown_backup_file: unknown, previous_destination: previous})
  end

  # Seeded a month before the scenario's clock, earlier than any other scenario's schedule
  # or run in this shared database falls due, so that at its slot it is the only due work.
  def prepare_behaviour(context, :second_family_handler, _args) do
    ensure_scheduler_storage()
    key = schedule_key("second-family")
    seeded_at = DateTime.add(@behaviour_now, -30 * 86_400)
    :ok = Schedules.put_test_schedule(key, "family", "fixture", seeded_at)
    Map.merge(context, %{schedule_key: key, schedule_due_at: seeded_at})
  end

  # The panels the contexts declare, and each owner's saved state, all isolated from the
  # run's shared state: the storage pointer the run uses, copied to a private path the
  # scenario points Storage at; a private backup configuration path with nothing saved; and
  # a backup-handler schedule of its own, disabled and not due, so no coordinator claims it.
  def prepare_behaviour(context, :typed_settings_panels, _args) do
    context = prepare_backup_destination(context)
    key = schedule_key("allowlist")

    :ok =
      Schedules.put_schedule!(%{
        schedule_key: key,
        handler_key: "prod_sqlite_backup",
        schedule_context: "admin_system",
        cadence: "daily",
        daily_at_utc: "19:00",
        enabled: false,
        expiration_kind: "never",
        expires_at: nil,
        max_occurrences: nil,
        claimed_occurrences: 0,
        expired_at: nil,
        next_run_at: DateTime.add(@behaviour_now, 365 * 86_400),
        revision: 1,
        inserted_at: @behaviour_now,
        updated_at: @behaviour_now
      })

    Map.merge(context, %{
      declared_panels: Operations.admin_panels(),
      allowlist_schedule_key: key,
      storage_pointer: isolated_storage_pointer!()
    })
  end

  def prepare_behaviour(context, :expiry_policies, _args) do
    ensure_scheduler_storage()
    key = schedule_key("expires")

    :ok =
      Schedules.put_test_schedule(key, "family", "fixture", @behaviour_now, max_occurrences: 1)

    policies = [
      %{expiration_kind: "never"},
      %{expiration_kind: "at", expires_at: DateTime.add(@behaviour_now, 60)},
      %{expiration_kind: "after_occurrences", claimed_occurrences: 0, max_occurrences: 1}
    ]

    Map.merge(context, %{schedule_key: key, expiration_policies: policies})
  end

  def prepare_behaviour(context, :no_storage_configuration, _args) do
    pointer = sqlite_storage_pointer_path()
    System.put_env("BNEST_STORAGE_CONFIG", pointer)
    ExUnit.Callbacks.on_exit(fn -> System.delete_env("BNEST_STORAGE_CONFIG") end)
    Map.put(context, :storage_pointer, pointer)
  end

  # Counts every request routed to the storage UI and every mount of its LiveView from here
  # on, so the When's effect on the count is observed rather than assumed.
  def prepare_behaviour(context, :storage_ui_not_visited, _args) do
    visits = :counters.new(1, [])
    handler = "bnest-behaviour-storage-ui-" <> unique_suffix()

    :ok =
      :telemetry.attach_many(
        handler,
        [[:phoenix, :router_dispatch, :start], [:phoenix, :live_view, :mount, :start]],
        &__MODULE__.count_storage_ui_visit/4,
        visits
      )

    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(handler) end)
    Map.put(context, :storage_ui_visits, visits)
  end

  def prepare_behaviour(%{view: view} = context, :migration_not_started, _args) do
    unless has_element?(view, "section[aria-label='Migration status']", "Not started") do
      raise "storage migration already started"
    end

    Map.put(context, :migration_not_started?, true)
  end

  def prepare_behaviour(context, :admin_opened_storage_settings, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])

    context
    |> establish_identity(:admin)
    |> open("/storage")
  end

  def prepare_behaviour(context, :empty_isolated_database, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])
    runtime = TestRuntimeRoot.create!("sqlite-storage-schema")

    ExUnit.Callbacks.on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    Map.put(context, :sqlite_database_path, Path.join(runtime.sqlite_path, "bnest.sqlite3"))
  end

  def prepare_behaviour(context, :flat_primary_default_location, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])
    runtime = TestRuntimeRoot.create!("sqlite-storage-migration")

    ExUnit.Callbacks.on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    identity = seed_flat_fixtures!(runtime.path)

    context
    |> Map.put(:flat_root, runtime.path)
    |> Map.put(:sqlite_database_path, Path.join(runtime.sqlite_path, "bnest.sqlite3"))
    |> Map.put(:migration_identity, identity)
  end

  def prepare_behaviour(context, :migration_stopped_after_progress, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])
    repo = sqlite_repo_started!(context.sqlite_database_path)
    Ecto.Migrator.run(repo, sqlite_migrations_path(), :up, all: true)
    SqliteMigration.run(context.flat_root, repo)
    context
  end

  # Retirement removes every verified file under the flat root, so this flat root is a
  # subdirectory of the marked SQLite run root and never contains a run marker itself.
  def prepare_behaviour(context, :all_verification_checks_pass, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])
    runtime = TestRuntimeRoot.create!("sqlite-storage-authority")

    ExUnit.Callbacks.on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    flat_root = Path.join(runtime.sqlite_path, "flat-source")
    File.mkdir_p!(flat_root)
    identity = seed_flat_fixtures!(flat_root)
    journey_records = seed_journey_records!(flat_root, identity.user_id)
    database_path = Path.join(runtime.sqlite_path, StorageLocation.filename())
    {:ok, _config} = Storage.persist_directory(runtime.sqlite_path)
    repo = sqlite_repo_started!(database_path)
    Ecto.Migrator.run(repo, sqlite_migrations_path(), :up, all: true)

    Map.merge(context, %{
      flat_root: flat_root,
      sqlite_database_path: database_path,
      migration_identity: identity,
      journey_records: journey_records,
      rollback_reader: FileRecordBackend.new!(runtime.path),
      migration_run_result: SqliteMigration.run(flat_root, repo)
    })
  end

  def prepare_behaviour(context, :malformed_or_changed_source, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])
    broken_path = Path.join(context.flat_root, "system/manifests/broken-manifest.json")
    File.mkdir_p!(Path.dirname(broken_path))
    File.write!(broken_path, "not-json")
    context
  end

  def prepare_behaviour(context, :non_admin_family_member, _args),
    do: establish_identity(context, :child)

  def prepare_behaviour(context, :legacy_authoritative_sqlite, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])
    runtime = TestRuntimeRoot.create!("sqlite-storage-lifecycle")

    ExUnit.Callbacks.on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    flat_root = Path.join(runtime.sqlite_path, "flat-source")
    legacy_directory = Path.join(runtime.sqlite_path, "legacy-config")
    destination = Path.join(runtime.sqlite_path, "relocated")
    File.mkdir_p!(flat_root)
    File.write!(Path.join(flat_root, ".gitkeep"), "")
    seed_flat_fixtures!(flat_root)
    {:ok, _config} = Storage.persist_directory(legacy_directory)
    database_path = Path.join(legacy_directory, StorageLocation.filename())
    repo = sqlite_repo_started!(database_path)
    Ecto.Migrator.run(repo, sqlite_migrations_path(), :up, all: true)
    SqliteMigration.run(flat_root, repo)
    :ok = SqliteMigration.activate!(repo)

    Map.merge(context, %{
      flat_root: flat_root,
      legacy_database_path: database_path,
      relocation_destination: destination
    })
  end

  def prepare_behaviour(context, :routed_storage_generation_proven, _args) do
    context = prepare_behaviour(context, :legacy_authoritative_sqlite, [])
    {:ok, config} = SqliteRelocation.run(context.relocation_destination)
    Map.put(context, :storage_generation, config["databaseGeneration"])
  end

  def prepare_behaviour(context, :denied_settings_visitor, _args),
    do: establish_identity(context, :child)

  def prepare_behaviour(context, state, args),
    do: IntegrationFamilyChatDriver.prepare_behaviour(context, state, args)

  @impl true
  def perform_behaviour(context, :open_protected_route, [route]) do
    {response, record_accesses} = record_accesses_during(fn -> get(context.conn, route) end)
    redirected = response.status == 302

    login_response =
      if redirected,
        do: response |> recycle() |> get(redirected_to(response)),
        else: response

    login_form_only =
      route == "/" and login_response.status == 200 and
        String.contains?(login_response.resp_body, ~s(id="login-form")) and
        not String.contains?(login_response.resp_body, ~s(data-role="admin-settings-entry")) and
        not String.contains?(login_response.resp_body, ~s(data-role="chat-entry"))

    Map.merge(context, %{
      response: response,
      redirected: redirected,
      login_form_only: login_form_only,
      record_accesses: record_accesses
    })
  end

  def perform_behaviour(context, :bootstrap_accounts, _args) do
    accepts_short? = Credentials.valid_password?("a_1")
    accepts_long? = Credentials.valid_password?(String.duplicate("é", 129) <> "_1")

    rejects_missing_requirement? =
      Enum.all?(["password_", "password1", "123_"], fn password ->
        not Credentials.valid_password?(password)
      end)

    accounts = [
      %{"username" => "test-user-family-admin", "password" => "a_1", "roles" => ["admin"]},
      %{"username" => "test-user-family-child", "password" => "é_1", "roles" => ["children"]}
    ]

    first_result = Bootstrap.create(context.identity_store, accounts)
    second_result = Bootstrap.create(context.identity_store, accounts)

    Map.merge(context, %{
      bootstrap_first_result: first_result,
      bootstrap_second_result: second_result,
      passwords_without_length_rule: accepts_short? and accepts_long?,
      password_requirements_enforced: rejects_missing_requirement?
    })
  end

  def perform_behaviour(context, :login, _args) do
    {username, password} = BnestAppWeb.ConnCase.test_credentials()
    {:ok, token} = BnestApp.Identity.login(username, password)
    Map.put(context, :token, token)
  end

  def perform_behaviour(context, :logout_current_browser, _args) do
    :ok = BnestApp.Identity.logout(context.token)
    context
  end

  def perform_behaviour(context, :reload_same_browser, _args),
    do: Map.put(context, :reload_result, BnestApp.Identity.current_user(context.token))

  def perform_behaviour(context, :logout_browser_a, _args) do
    :ok = BnestApp.Identity.logout(context.token_a)
    context
  end

  def perform_behaviour(context, :authorize_own_data, _args) do
    allowed = Authorization.allow?(context.auth_user, :use_chat, "user-integration")

    denied =
      not Authorization.allow?(
        context.auth_user,
        :manage_accounts,
        "user-integration"
      )

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
    Map.put(context, :import_results, [
      Import.absent_theme(context.central_store, context.user_id)
    ])
  end

  def perform_behaviour(context, :confirm_imports, _args) do
    results =
      Enum.map(
        context.browser_sources,
        &Import.browser(context.central_store, context.user_id, &1)
      )

    Map.put(context, :import_results, results)
  end

  def perform_behaviour(context, :retry_import, _args) do
    before = import_envelope_count(context.central_store, context.user_id)
    result = Import.browser(context.central_store, context.user_id, chat_source())
    Map.merge(context, %{envelopes_before_retry: before, retry_result: result})
  end

  def perform_behaviour(context, :write_stale_record, _args) do
    [source] = context.browser_sources

    Map.put(
      context,
      :stale_result,
      Import.browser(context.central_store, context.user_id, source)
    )
  end

  # The routed import page receives what its browser hook would report, the unrelated key
  # included, so the `imports-accepted` push is the only thing that decides which keys the
  # browser removes.
  def perform_behaviour(context, :accept_and_read_back, _args) do
    {:ok, view, _html} = live(context.conn, "/data-migration")
    sources = Enum.map(context.browser_storage, &Map.put(&1, "present", true))
    render_hook(view, "browser-sources", %{"sources" => sources})
    view |> element("button[phx-click=confirm-imports]") |> render_click()
    %{proxy: {ref, _topic, _pid}} = view

    cleared =
      receive do
        {^ref, {:push_event, "imports-accepted", %{"storageKeys" => keys}}} -> keys
      after
        1_000 -> raise "the import page sent no cleanup instruction"
      end

    Map.put(context, :cleared_storage_keys, cleared)
  end

  # The user opens the saved chat, whose Codex thread the mount tries to resume, and sends the
  # next message. The page the mount rendered is kept, since the send clears its alert.
  def perform_behaviour(context, :continue_chat, _args) do
    {:ok, view, html} = live(context.conn, "/chat")
    render_submit(view, "send", %{"chat" => %{"prompt" => "Continue after resume"}})

    Map.merge(context, %{view: view, route: "/chat", reopened_page: LazyHTML.from_fragment(html)})
  end

  def perform_behaviour(context, :start_managed_migration, _args) do
    visits_before = :counters.get(context.storage_ui_visits, 1)
    config = FileConfigStore.ensure_default!()

    Map.merge(context, %{
      storage_config: config,
      written_pointer_path: FileConfigStore.pointer_path(),
      storage_ui_visits_during_migration:
        :counters.get(context.storage_ui_visits, 1) - visits_before
    })
  end

  def perform_behaviour(context, :enter_valid_folder, _args) do
    custom = Path.join(System.tmp_dir!(), "bnest-storage-custom-" <> unique_suffix())
    File.mkdir_p!(custom)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(custom) end)

    persist_storage_from_view(context, custom)
  end

  def perform_behaviour(
        %{identity_role: :admin, migration_not_started?: true, view: _view} = context,
        :enter_private_folder_beneath_sticky_shared_directory,
        _args
      ) do
    shared = Path.join(System.tmp_dir!(), "bnest-storage-shared-" <> unique_suffix())
    custom = Path.join(shared, "private")
    File.mkdir_p!(custom)
    {_output, 0} = System.cmd("chmod", ["1777", shared])
    File.chmod!(custom, 0o700)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(shared) end)

    persist_storage_from_view(context, custom)
  end

  def perform_behaviour(context, :enter_unsafe_folder, _args) do
    unsafe = "relative/unsafe/path"

    html =
      context.view
      |> form("form[phx-submit=check_folder]", %{"directory" => unsafe})
      |> render_submit()

    context
    |> Map.put(:unsafe_response, LazyHTML.from_fragment(html))
    |> Map.put(:requested_directory, unsafe)
  end

  def perform_behaviour(context, :apply_migration_set_twice, _args) do
    repo = sqlite_repo_started!(context.sqlite_database_path)
    path = sqlite_migrations_path()

    {:ok, _versions, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, path, :up, all: true))

    before_second = repo.query!("SELECT sql FROM sqlite_master ORDER BY sql").rows

    {:ok, _versions, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, path, :up, all: true))

    after_second = repo.query!("SELECT sql FROM sqlite_master ORDER BY sql").rows

    context
    |> Map.put(:schema_before_second_apply, before_second)
    |> Map.put(:schema_after_second_apply, after_second)
  end

  def perform_behaviour(context, :run_managed_storage_migration, _args) do
    repo = sqlite_repo_started!(context.sqlite_database_path)
    Ecto.Migrator.run(repo, sqlite_migrations_path(), :up, all: true)
    Map.put(context, :migration_run_result, SqliteMigration.run(context.flat_root, repo))
  end

  def perform_behaviour(context, :retry_same_migration, _args) do
    repo = sqlite_repo_started!(context.sqlite_database_path)
    before_count = repo.query!("SELECT count(*) FROM bnest_migration_items").rows

    result = SqliteMigration.run(context.flat_root, repo)

    after_count = repo.query!("SELECT count(*) FROM bnest_migration_items").rows

    context
    |> Map.put(:migration_run_result, result)
    |> Map.put(:item_count_before_retry, before_count)
    |> Map.put(:item_count_after_retry, after_count)
  end

  def perform_behaviour(context, :commit_authority_switch, _args) do
    repo = sqlite_repo_started!(context.sqlite_database_path)
    :ok = SqliteMigration.activate!(repo)
    Map.put(context, :storage_config, elem(FileConfigStore.read(), 1))
  end

  # Bound to a Then step: production retirement runs against the pointer's own generation,
  # and any identity source still on disk afterwards fails the step.
  def perform_behaviour(context, :retire_flat_identity_sources, _args) do
    identity = context.migration_identity

    {:ok, %{"flatFilesRetiredAt" => _retired_at}} =
      Storage.retire(context.flat_root, Storage.database_generation(), false)

    remaining =
      [
        "system/bootstrap.json",
        "system/accounts/#{identity.user_id}.json",
        "system/usernames/#{identity.username}.json"
      ]
      |> Enum.filter(&File.exists?(Path.join(context.flat_root, &1)))

    unless remaining == [], do: raise("flat identity sources remain: #{inspect(remaining)}")
    Map.put(context, :flat_identity_sources_remaining, remaining)
  end

  def perform_behaviour(context, :verify_migration, _args) do
    repo = sqlite_repo_started!(context.sqlite_database_path)
    Ecto.Migrator.run(repo, sqlite_migrations_path(), :up, all: true)
    result = SqliteMigration.run(context.flat_root, repo)
    Map.put(context, :migration_run_result, result)
  end

  def perform_behaviour(context, :open_storage_settings_route, _args) do
    Map.put(context, :response, get(context.conn, "/storage"))
  end

  def perform_behaviour(context, :relocate_storage, _args),
    do:
      Map.put(
        context,
        :relocation_result,
        SqliteRelocation.run(context.relocation_destination)
      )

  def perform_behaviour(context, :retire_legacy_storage, _args),
    do:
      Map.put(
        context,
        :retirement_result,
        FlatRetirement.run(context.flat_root, context.storage_generation)
      )

  def perform_behaviour(context, :open_admin_settings, _args) do
    response = get(context.conn, "/admin/settings")
    home = get(context.conn, "/")
    Map.merge(context, %{response: response, home_response: home})
  end

  # The page shows the backup destination, so it is given an isolated working default: the
  # test run's own repository root fails closed, and the page would fall back to an empty
  # inventory.
  def perform_behaviour(context, :open_schedules_from_home, _args) do
    _default = TestBackupDestination.default_repository!("schedules-" <> unique_suffix())
    response = get(context.conn, "/admin/settings/schedules")
    Map.put(context, :response, response)
  end

  def perform_behaviour(context, :open_admin_settings_from_home, _args) do
    response = get(context.conn, "/admin/settings")
    Map.put(context, :response, response)
  end

  # The daily backup handler resolves its destination again when it runs, so its verified
  # receipt is the public result produced for the resolved default.
  def perform_behaviour(context, :resolve_backup_destination, _args) do
    {:ok, location} = result = Backup.destination()
    key = schedule_key("default")
    :ok = Schedules.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)
    {:ok, claim} = Scheduler.claim_setup(key, location.destination_id, @behaviour_now)

    Map.merge(context, %{
      backup_resolution: result,
      backup_execution: ScheduledBackupTask.execute(claim, @behaviour_now)
    })
  end

  def perform_behaviour(context, :save_backup_override, _args) do
    result = Backup.save_destination(context.backup_directory)
    {:ok, location} = result
    key = schedule_key("save")
    :ok = Schedules.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)
    before = Schedules.run_count()
    {:ok, first} = Scheduler.claim_setup(key, location.destination_id, @behaviour_now)
    {:ok, second} = Scheduler.claim_setup(key, location.destination_id, @behaviour_now)

    Map.merge(context, %{
      backup_save_result: result,
      first_setup_claim: first,
      second_setup_claim: second,
      setup_run_delta: Schedules.run_count() - before
    })
  end

  def perform_behaviour(context, :restart_scheduler, _args) do
    before = context.schedule_before_restart
    supervisor = Process.whereis(BnestApp.Supervisor)
    scheduler = Process.whereis(BnestApp.Scheduler)
    if is_pid(scheduler), do: Process.exit(scheduler, :kill)
    await_scheduler_restart(supervisor, scheduler, 100)

    Map.merge(context, %{
      schedule_after_restart: Scheduler.get_schedule(context.schedule_key),
      scheduler_restarted?: true,
      schedule_before_restart: before
    })
  end

  def perform_behaviour(context, :reconcile_startup, _args) do
    claims = Scheduler.claim_due(@behaviour_now)
    claim = Enum.find(claims, &(&1.schedule_key == context.schedule_key))

    Map.merge(context, %{
      reconciled_claim: claim,
      reconciled_schedule: Scheduler.get_schedule(context.schedule_key)
    })
  end

  # Step-binding collision fix (adapter change; mirrors
  # `BnestApp.Behaviour.UnitHomePageDriver`'s identical fix -- see its own
  # comment and learnings.md's Phase 5 entry): "the backup handler runs" is
  # shared verbatim by the pre-existing scheduled-backup feature (below) and
  # by family_chat_operations.feature's capacity scenario, and ExBDD step
  # text is matched globally across all `test/behaviour/steps/*.exs` files,
  # not per feature file, so only one driver clause can own this exact text.
  # The family-chat scenario's own `:insufficient_capacity` Given step is
  # the unambiguous signal for which one applies.
  def perform_behaviour(context, :run_backup_handler, _args)
      when is_map_key(context, :family_chat_backup_capacity) do
    IntegrationFamilyChatDriver.perform_behaviour(
      context,
      :backup_runs_full_duration,
      []
    )
  end

  def perform_behaviour(context, :run_backup_handler, _args),
    do:
      Map.put(
        context,
        :backup_execution,
        ScheduledBackupTask.execute(context.backup_claim, @behaviour_now)
      )

  def perform_behaviour(context, :reconcile_overlap, _args) do
    claims =
      1..2
      |> Task.async_stream(fn _coordinator -> Scheduler.claim_due(@behaviour_now) end,
        max_concurrency: 2
      )
      |> Enum.flat_map(fn {:ok, rows} ->
        Enum.filter(rows, &(&1.schedule_key == context.schedule_key))
      end)

    [claim] = claims

    {:retryable, attempt_2} =
      ScheduleStore.fail_attempt(
        Scheduler.store(),
        claim.run_id,
        claim.attempt,
        :capacity,
        @behaviour_now
      )

    at_2 = DateTime.add(@behaviour_now, 5 * 60)
    retried_2 = Enum.find(Scheduler.claim_due(at_2), &(&1.run_id == claim.run_id))

    {:retryable, attempt_3} =
      ScheduleStore.fail_attempt(
        Scheduler.store(),
        claim.run_id,
        retried_2.attempt,
        :capacity,
        at_2
      )

    at_3 = DateTime.add(at_2, 30 * 60)
    retried_3 = Enum.find(Scheduler.claim_due(at_3), &(&1.run_id == claim.run_id))

    {:failed, failed} =
      ScheduleStore.fail_attempt(
        Scheduler.store(),
        claim.run_id,
        retried_3.attempt,
        :capacity,
        at_3
      )

    Map.merge(context, %{overlap_claims: claims, retry_attempts: [attempt_2, attempt_3, failed]})
  end

  def perform_behaviour(context, :verify_new_backup, _args) do
    {:ok, location} = Backup.save_destination(context.backup_directory)
    key = schedule_key("retention")
    :ok = Schedules.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)

    receipts =
      Enum.map(0..8, fn days ->
        at = DateTime.add(@behaviour_now, -days * 86_400)
        {:ok, claim} = Scheduler.claim_setup(key, "#{location.destination_id}-#{days}", at)
        {:ok, receipt} = ScheduledBackupTask.execute(claim, at)
        receipt
      end)

    Map.put(context, :retention_receipts, receipts)
  end

  # The application's running coordinator reconciles once at the slot's clock, so it
  # claims the slot and the shared `Scheduler.Tasks` supervisor runs it. The driver claims
  # and runs nothing itself; `SchedulerDispatch.coordinate/2` records what the supervisor's
  # processes ran. Should the coordinator claim any other run, a backup resolves an
  # isolated destination, never the operator's configured one.
  def perform_behaviour(context, :run_second_handler, _args) do
    _location = TestBackupDestination.configure!("second-family-" <> unique_suffix())

    dispatch =
      SchedulerDispatch.coordinate(context.schedule_key, fn ->
        reconcile_at(context.schedule_due_at)
      end)

    Map.put(context, :family_handler_dispatch, dispatch)
  end

  def perform_behaviour(context, :reconcile_expiry, _args) do
    initial = Scheduler.claim_due(@behaviour_now)
    first = Enum.find(initial, &(&1.schedule_key == context.schedule_key))

    {:retryable, retry} =
      ScheduleStore.fail_attempt(
        Scheduler.store(),
        first.run_id,
        first.attempt,
        :capacity,
        @behaviour_now
      )

    later = Scheduler.claim_due(DateTime.add(@behaviour_now, 86_400))

    Map.merge(context, %{
      expiration_eligibility:
        Enum.map(context.expiration_policies, &Policy.eligible?(&1, @behaviour_now)),
      expiration_first_claim: first,
      expiration_retry: retry,
      expiration_later_claims: later
    })
  end

  def perform_behaviour(context, action, args),
    do: IntegrationFamilyChatDriver.perform_behaviour(context, action, args)

  @impl true
  def behaviour_outcome?(context, :redirected_to_login, _args), do: context.redirected
  def behaviour_outcome?(context, :login_form_only, _args), do: context.login_form_only
  # The trace saw its own probe read, so an empty list here is measured: the request read and
  # wrote no record before the guard redirected it.
  def behaviour_outcome?(context, :no_user_data_access, _args),
    do: context.redirected and context.record_accesses == []

  # The scenario's own runtime root holds the bootstrap journal, while the running app's
  # identity is already set up, so the `/setup` template is rendered for this store's status
  # rather than requested over HTTP.
  def behaviour_outcome?(context, :irreversible_warning, _args) do
    context.identity_store
    |> render_setup()
    |> LazyHTML.query("[aria-labelledby=setup-closed-title]")
    |> LazyHTML.text()
    |> String.contains?("password recovery are unavailable")
  end

  def behaviour_outcome?(context, :accounts_created_once, _args),
    do:
      match?({:ok, [_admin, _child]}, context.bootstrap_first_result) and
        context.bootstrap_second_result == {:error, :closed}

  def behaviour_outcome?(context, :setup_closed, _args),
    do:
      Bootstrap.status(context.identity_store) == :closed and
        context.identity_store
        |> render_setup()
        |> LazyHTML.query("#bootstrap-form")
        |> Enum.empty?()

  def behaviour_outcome?(context, :passwords_without_length_rule, _args),
    do: context.passwords_without_length_rule

  def behaviour_outcome?(context, :password_requirements_enforced, _args),
    do: context.password_requirements_enforced

  def behaviour_outcome?(context, :protected_home_available, _args),
    do: protected_home?(browser_home(context.token))

  def behaviour_outcome?(context, :current_browser_logged_out, _args),
    do:
      login_redirect?(browser_home(context.token)) and
        BnestApp.Identity.current_user(context.token) == {:error, :unauthenticated}

  def behaviour_outcome?(context, :no_plaintext_password, _args) do
    bytes =
      context.identity_store.records.root
      |> Path.join("**/*.json")
      |> Path.wildcard()
      |> Enum.map_join(&File.read!/1)

    String.starts_with?(context.verifier, "$argon2id$") and
      Argon2CredentialHasher.verify(context.identity_password, context.verifier) and
      not String.contains?(bytes, context.identity_password)
  end

  def behaviour_outcome?(context, :same_browser_authenticated, _args),
    do: match?({:ok, %{"userId" => _user_id}}, context.reload_result)

  def behaviour_outcome?(context, :browser_a_logged_out, _args),
    do:
      login_redirect?(browser_home(context.token_a)) and
        BnestApp.Identity.current_user(context.token_a) == {:error, :unauthenticated}

  def behaviour_outcome?(context, :browser_b_authenticated, _args),
    do: protected_home?(browser_home(context.token_b))

  def behaviour_outcome?(context, :operation_allowed, _args), do: context.operation_allowed

  def behaviour_outcome?(context, :administration_denied, _args),
    do: context.administration_denied

  def behaviour_outcome?(context, :denied_before_repository, _args), do: context.cross_user_denied

  # The run keeps its configuration home in the private directory `BNEST_STORAGE_CONFIG` names,
  # never the real `~/.config/bnest`. The pointer the When wrote must be there, private, outside
  # the database directory, and hold the configuration the migration chose.
  def behaviour_outcome?(context, :pointer_under_configuration_home, _args) do
    path = context.written_pointer_path

    with {:ok, bytes} <- File.read(path),
         {:ok, written} <- Jason.decode(bytes) do
      path == context.storage_pointer and written == context.storage_config and
        permission_bits(path) == 0o600 and permission_bits(Path.dirname(path)) == 0o700 and
        not String.starts_with?(path, context.storage_config["databaseDirectory"] <> "/")
    else
      _failure -> false
    end
  end

  def behaviour_outcome?(context, :sqlite_under_production_data, _args),
    do: context.storage_config["databaseDirectory"] == Storage.default_directory()

  def behaviour_outcome?(context, :no_browser_confirmation, _args),
    do:
      context.storage_ui_visits_during_migration == 0 and
        File.regular?(context.written_pointer_path)

  def behaviour_outcome?(context, :folder_normalized_with_fixed_filename, _args) do
    case FileConfigStore.read() do
      {:ok, config} ->
        config["databaseFilename"] == StorageLocation.filename() and
          config["databaseDirectory"] == Path.expand(context.requested_directory)

      {:error, _reason} ->
        false
    end
  end

  def behaviour_outcome?(_context, :validated_location_stored_privately, _args) do
    stat = File.stat!(FileConfigStore.pointer_path())
    Bitwise.band(stat.mode, 0o777) == 0o600
  end

  def behaviour_outcome?(context, :safe_correction_explained, _args),
    do:
      context.unsafe_response
      |> LazyHTML.query("[role=alert]")
      |> LazyHTML.text()
      |> String.contains?("Enter an absolute server-local folder")

  def behaviour_outcome?(_context, :no_storage_created, _args),
    do: FileConfigStore.read() == {:error, :absent}

  def behaviour_outcome?(context, outcome, _args)
      when outcome in [:schema_matches_checksum, :no_duplicate_schema_objects] do
    context.schema_before_second_apply == context.schema_after_second_apply and
      context.schema_before_second_apply != []
  end

  def behaviour_outcome?(context, :deterministic_inventory, _args) do
    items = SqliteMigration.inventory(context.flat_root)
    items != [] and items == Enum.sort(items)
  end

  def behaviour_outcome?(context, :database_under_resolved_directory, _args),
    do: File.exists?(context.sqlite_database_path)

  def behaviour_outcome?(context, :all_valid_items_accepted, _args) do
    inventory_count = context.flat_root |> SqliteMigration.inventory() |> length()

    context.migration_run_result.blocked == 0 and
      context.migration_run_result.accepted == inventory_count
  end

  def behaviour_outcome?(context, :checksum_evidence_present, _args) do
    repo = sqlite_repo_started!(context.sqlite_database_path)

    %{rows: rows} =
      repo.query!(
        "SELECT source_sha256, target_sha256 FROM bnest_migration_items WHERE outcome = 'accepted'"
      )

    rows != [] and
      Enum.all?(rows, fn [source, target] -> is_binary(source) and is_binary(target) end)
  end

  def behaviour_outcome?(context, :normal_reads_match, _args) do
    repo = sqlite_repo_started!(context.sqlite_database_path)
    SqliteMigration.parity_ok?(context.flat_root, repo)
  end

  def behaviour_outcome?(context, :accepted_items_not_duplicated, _args),
    do: context.item_count_before_retry == context.item_count_after_retry

  def behaviour_outcome?(context, :remaining_items_continue, _args),
    do: context.migration_run_result.accepted > 0

  def behaviour_outcome?(_context, :future_reads_use_sqlite, _args),
    do: FileConfigStore.phase() == :sqlite_primary

  # A login after the switch writes its session through `Records`. The write must land in
  # SQLite, not the flat root, and the flat reader a rollback falls back to must accept it.
  def behaviour_outcome?(context, :writes_compatible_with_rollback, _args) do
    identity = context.migration_identity
    reader = context.rollback_reader

    with {:ok, token} <- BnestApp.Identity.login(identity.username, identity.password),
         digest = BnestApp.Identity.session_digest(token),
         {:ok, session} <- Records.read(:session, digest),
         false <- File.exists?(Path.join(context.flat_root, "system/sessions/#{digest}.json")),
         {:ok, ^session} <- FileRecordBackend.put_new(reader, :session, digest, session) do
      FileRecordBackend.read(reader, :session, digest) == {:ok, session}
    else
      _failure -> false
    end
  end

  # The flat files are retired by now, so each journey can only be served from SQLite.
  def behaviour_outcome?(context, :journeys_survive_restart, _args) do
    SqliteCoordinator.stop()
    _repo = sqlite_repo_started!(context.sqlite_database_path)
    identity = context.migration_identity

    with [] <- context.flat_identity_sources_remaining,
         :closed <- BnestApp.Identity.setup_status(),
         {:ok, token} <- BnestApp.Identity.login(identity.username, identity.password),
         {:ok, %{"normalizedUsername" => username, "userId" => user_id}} <-
           BnestApp.Identity.current_user(token),
         true <- username == identity.username,
         true <-
           Enum.all?(context.journey_records, fn {type, record} ->
             Records.read(type, user_id) == {:ok, record}
           end),
         true <- Preferences.theme(user_id) == context.journey_records.theme["theme"],
         true <-
           SifatAllah.load_progress(user_id) == {:ok, context.journey_records.sifat_allah},
         {:ok, _transcript, chat} <- CodexChat.load_transcript(user_id),
         true <- chat == context.journey_records.chat,
         conn = Plug.Test.put_req_cookie(Phoenix.ConnTest.build_conn(), "_bnest_identity", token),
         %{status: 200, resp_body: home} <- get(conn, "/"),
         true <- String.contains?(home, ~s(data-theme="dark")),
         %{status: 200} <- get(conn, "/admin/settings"),
         :ok <- BnestApp.Identity.logout(token),
         {:error, :unauthenticated} <- BnestApp.Identity.current_user(token) do
      true
    else
      _failure -> false
    end
  end

  def behaviour_outcome?(_context, :sqlite_not_authoritative, _args),
    do: FileConfigStore.phase() == :flat_primary

  def behaviour_outcome?(context, :source_and_service_unchanged, _args),
    do: File.exists?(Path.join(context.flat_root, "system/bootstrap.json"))

  def behaviour_outcome?(context, :value_free_retry_category, _args),
    do: context.migration_run_result.blocked > 0

  def behaviour_outcome?(context, :storage_access_denied, _args),
    do: context.response.status == 404

  def behaviour_outcome?(context, :no_host_path_or_inventory_revealed, _args),
    do: context.response.resp_body == "Not found"

  def behaviour_outcome?(context, :pointer_relocated_atomically, _args),
    do:
      match?({:ok, _config}, context.relocation_result) and
        FileConfigStore.resolved_database_path() ==
          Path.join(context.relocation_destination, StorageLocation.filename())

  def behaviour_outcome?(context, :legacy_sqlite_retained_until_proof, _args) do
    {:ok, config} = context.relocation_result
    is_binary(config["databaseGeneration"]) and File.exists?(context.legacy_database_path)
  end

  def behaviour_outcome?(context, :verified_legacy_sources_removed, _args),
    do:
      match?({:ok, _config}, context.retirement_result) and
        not File.exists?(context.legacy_database_path) and
        not File.exists?(Path.join(context.flat_root, "system/bootstrap.json"))

  def behaviour_outcome?(context, :config_and_placeholders_preserved, _args) do
    match?(
      {:ok, %{"flatFilesRetiredAt" => retired_at}} when is_binary(retired_at),
      FileConfigStore.read()
    ) and File.exists?(Path.join(context.flat_root, ".gitkeep"))
  end

  def behaviour_outcome?(context, :immutable_envelopes, _args) do
    Enum.all?(context.import_results, fn
      {:ok, %{import_id: import_id}} ->
        match?(
          {:ok, %{"payloadEncoding" => "utf8-string"}},
          FileRecordBackend.read(
            context.central_store,
            :browser_import,
            {context.user_id, import_id}
          )
        )

      _failure ->
        false
    end)
  end

  def behaviour_outcome?(context, :normalized_records_read, _args) do
    Enum.all?([:chat, :sifat_allah, :theme], fn type ->
      case FileRecordBackend.read(context.central_store, type, context.user_id) do
        {:ok, %{"ownerId" => owner}} -> owner == context.user_id
        _missing -> false
      end
    end)
  end

  def behaviour_outcome?(context, :absent_theme_recorded, _args) do
    with [{:ok, %{import_id: import_id}}] <- context.import_results,
         {:ok, %{"recoverySource" => %{"kind" => "browser-absence"}}} <-
           FileRecordBackend.read(context.central_store, :manifest, import_id) do
      true
    else
      _failure -> false
    end
  end

  def behaviour_outcome?(context, :no_theme_preference, _args),
    do:
      FileRecordBackend.read(context.central_store, :theme, context.user_id) == {:error, :missing}

  def behaviour_outcome?(context, :safe_rejected_import, _args),
    do: match?([{:error, :unsupported_source, _manifest}], context.import_results)

  def behaviour_outcome?(context, :source_and_record_unchanged, _args),
    do:
      FileRecordBackend.read(context.central_store, :chat, context.user_id) ==
        context.accepted_before

  def behaviour_outcome?(context, :idempotent_import_identity, _args),
    do: match?({:ok, %{import_id: id}} when id == context.first_import_id, context.retry_result)

  # The retry completes the interrupted import once: no second envelope, and the chat record
  # the interruption left absent now exists at its first revision.
  def behaviour_outcome?(context, :accepted_data_preserved, _args),
    do:
      import_envelope_count(context.central_store, context.user_id) ==
        context.envelopes_before_retry and
        match?(
          {:ok, %{"recordType" => "chat", "revision" => 0}},
          FileRecordBackend.read(context.central_store, :chat, context.user_id)
        )

  def behaviour_outcome?(context, :newer_record_preserved, _args),
    do:
      FileRecordBackend.read(context.central_store, :chat, context.user_id) ==
        {:ok, context.centralized_before}

  def behaviour_outcome?(context, :refresh_required, _args),
    do: match?({:error, :stale_revision, %{"status" => "retryable"}}, context.stale_result)

  # Bnest may tell the browser to clear the chat key only once that record reads back from
  # the server repository.
  def behaviour_outcome?(context, :only_accepted_key_cleared, _args),
    do:
      context.cleared_storage_keys == ["bnest.chat.v1"] and
        match?({:ok, %{"recordType" => "chat"}}, Records.read(:chat, context.user_id))

  # A change made after the accepted import: the theme request the root layout's script sends
  # goes through the routed endpoint. It must change the user's record in the server's
  # repository, and the home the server then renders must carry it while telling the browser
  # script to keep no copy of its own.
  def behaviour_outcome?(context, :server_only_persistence, _args) do
    user_id = context.user_id
    before = FileRecordBackend.read(context.central_store, :theme, user_id)
    requested = "dark"
    change = context.conn |> recycle() |> put("/preferences/theme", %{"theme" => requested})
    stored = FileRecordBackend.read(context.central_store, :theme, user_id)
    home = context.conn |> recycle() |> get("/")
    root = home.resp_body |> LazyHTML.from_document() |> LazyHTML.query("html")

    change.status == 204 and stored != before and
      match?({:ok, %{"ownerId" => ^user_id, "theme" => ^requested}}, stored) and
      Records.read(:theme, user_id) == stored and Preferences.theme(user_id) == requested and
      home.status == 200 and
      LazyHTML.attribute(root, "data-theme") == [requested] and
      LazyHTML.attribute(root, "data-theme-storage") == ["server"] and
      LazyHTML.attribute(root, "data-browser-persistence") == ["false"]
  end

  # The saved messages must still show, and the chat the facade loads must be the stored
  # record, leading with those messages on a thread other than the unavailable one.
  def behaviour_outcome?(context, :transcript_preserved, _args) do
    user_id = context.user_id
    saved_count = length(context.transcript_before)

    with true <-
           has_element?(context.view, "[data-role=user-message]", "Remember this transcript"),
         true <- has_element?(context.view, "[data-role=user-message]", "Continue after resume"),
         true <- has_element?(context.view, "[data-role=assistant-message]", "Saved response"),
         {:ok, transcript, record} <- CodexChat.load_transcript(user_id),
         {:ok, ^record} <- Records.read(:chat, user_id) do
      Enum.take(transcript.messages, saved_count) == context.transcript_before and
        transcript.thread_id != "unavailable-thread"
    else
      _lost -> false
    end
  end

  # Opening the chat reported the fresh conversation, and the saved chat left the unavailable
  # thread for one the new conversation has not named yet.
  def behaviour_outcome?(context, :fresh_conversation_reported, _args) do
    alert = context.reopened_page |> LazyHTML.query("[role=alert]") |> LazyHTML.text()

    String.contains?(alert, "transcript is preserved in a fresh conversation") and
      match?({:ok, %{thread_id: nil}, _record}, CodexChat.load_transcript(context.user_id))
  end

  def behaviour_outcome?(context, :default_backup_folder, _args),
    do:
      match?(
        {:ok, %{directory: directory}} when directory == context.default_backup_directory,
        context.backup_resolution
      )

  # The verified receipt names its destination only by id and its artifact only by basename;
  # neither the backup folder, the repository holding it, nor the live database path appears.
  def behaviour_outcome?(context, :no_private_path, _args) do
    with {:ok, location} <- context.backup_resolution,
         {:ok, receipt} <- context.backup_execution,
         true <- Receipt.valid?(receipt, location.destination_id) do
      encoded = Jason.encode!(receipt)

      Enum.all?(
        [context.backup_fixture_root, location.directory, Storage.database_path()],
        &(not String.contains?(encoded, &1))
      )
    else
      _failure -> false
    end
  end

  def behaviour_outcome?(context, :atomic_backup_config, _args) do
    with {:ok, location} <- context.backup_save_result,
         {:ok, bytes} <- File.read(context.backup_config_path),
         {:ok, %{"destinationDirectory" => directory, "schemaVersion" => 1}} <-
           Jason.decode(bytes),
         %File.Stat{mode: mode} <- File.stat!(context.backup_config_path) do
      directory == location.directory and Bitwise.band(mode, 0o777) == 0o600 and
        Path.wildcard(context.backup_config_path <> ".partial-*") == []
    else
      _failure -> false
    end
  end

  def behaviour_outcome?(context, :one_setup_claim, _args),
    do:
      context.first_setup_claim.run_id == context.second_setup_claim.run_id and
        context.setup_run_delta == 1

  def behaviour_outcome?(context, :schedule_persisted, _args),
    do: context.scheduler_restarted? and context.schedule_after_restart.enabled

  def behaviour_outcome?(context, :same_future_slot, _args),
    do: context.schedule_after_restart.next_run_at == context.schedule_before_restart.next_run_at

  def behaviour_outcome?(context, :latest_slot_only, _args),
    do:
      context.reconciled_claim.scheduled_for ==
        Policy.latest_slot(context.reconciled_schedule.daily_at_utc, @behaviour_now)

  def behaviour_outcome?(context, :next_future_day, _args),
    do:
      context.reconciled_schedule.next_run_at ==
        Policy.next_slot(context.reconciled_schedule.daily_at_utc, @behaviour_now)

  def behaviour_outcome?(context, :authoritative_vacuum, _args) do
    case context.backup_execution do
      {:ok, receipt} ->
        File.regular?(Path.join(context.backup_location.directory, receipt["artifactBasename"])) and
          receipt["sourceGeneration"] == FileConfigStore.database_generation()

      _failure ->
        false
    end
  end

  def behaviour_outcome?(context, :independent_proof, _args),
    do:
      match?(
        {:ok, %{"quickCheck" => "ok", "logicalProofSha256" => proof}} when byte_size(proof) == 64,
        context.backup_execution
      )

  def behaviour_outcome?(context, :single_nonoverlap_claim, _args),
    do: length(context.overlap_claims) == 1

  def behaviour_outcome?(context, :bounded_attempts, _args),
    do:
      Enum.map(context.retry_attempts, & &1.attempt) == [2, 3, 3] and
        List.last(context.retry_attempts).state == "failed"

  # Read from the served page: each persisted schedule is one row of its own context's
  # group, and the family row shows a safe status, as the FE e2e reads it.
  def behaviour_outcome?(context, :context_groups, _args) do
    %{family: family, admin_system: admin_system} = context.persisted_schedules
    page = LazyHTML.from_fragment(context.response.resp_body)
    family_row = schedule_row(page, "family-schedules-title", family)

    context.response.status == 200 and Enum.count(family_row) == 1 and
      family_row |> LazyHTML.text() |> String.match?(@safe_schedule_status) and
      Enum.count(schedule_row(page, "admin-schedules-title", admin_system)) == 1
  end

  def behaviour_outcome?(context, :typed_backup_link, _args),
    do:
      context.response.resp_body
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([data-schedule-key="prod-sqlite-backup-daily"] a))
      |> LazyHTML.attribute("href")
      |> Kernel.==(["/admin/settings/schedules"])

  def behaviour_outcome?(context, :not_found_before_reads, _args),
    do: context.response.status == 404 and context.response.resp_body == "Not found"

  def behaviour_outcome?(context, :no_admin_home_entry, _args),
    do:
      not String.contains?(context.home_response.resp_body, "Admin settings") and
        not String.contains?(context.home_response.resp_body, "Schedules &amp; backups")

  def behaviour_outcome?(context, :owned_retention, _args),
    do: length(Backup.owned_receipts(context.backup_directory)) == 7

  def behaviour_outcome?(context, :preserve_unowned, _args),
    do:
      File.exists?(context.unknown_backup_file) and
        File.exists?(Path.join(context.previous_destination, "previous-destination.txt"))

  # Read from the coordinator's observed dispatch: the registered fixture task alone ran,
  # once, under the shared supervisor, and returned its artifact-free receipt.
  def behaviour_outcome?(context, :shared_execution, _args),
    do:
      match?(
        {:ok, %{"artifactBasename" => nil}},
        SchedulerDispatch.coordinated_result(context.family_handler_dispatch)
      )

  def behaviour_outcome?(context, :shared_inventory, _args),
    do:
      Enum.any?(Scheduler.family_inventory(), fn schedule ->
        schedule.schedule_key == context.schedule_key and schedule.last_run_state == "verified"
      end)

  # Every declared panel renders as one link to its path, under its label.
  def behaviour_outcome?(context, :panels_discoverable, _args),
    do:
      context.response.status == 200 and
        context.response.resp_body
        |> rendered_panels()
        |> Enum.map(&Map.take(&1, [:href, :label]))
        |> Kernel.==(Enum.map(context.declared_panels, &%{href: &1.path, label: &1.label}))

  # Each rendered panel names its declared owner and editable fields, and that owner, driven
  # through its facade, refuses or ignores every field outside them and keeps its stored
  # state; a panel whose owner has no proof here fails.
  def behaviour_outcome?(context, :owner_allowlists, _args) do
    panels = rendered_panels(context.response.resp_body)

    declared =
      Enum.map(
        context.declared_panels,
        &%{owner: inspect(&1.owner), fields: Enum.join(&1.editable_fields, ",")}
      )

    Enum.map(panels, &Map.take(&1, [:owner, :fields])) == declared and
      Enum.all?(panels, &owner_saves_only_allowlisted?(context, &1))
  end

  def behaviour_outcome?(context, :expiry_blocks_future, _args) do
    same_schedule_claims =
      Enum.filter(context.expiration_later_claims, &(&1.schedule_key == context.schedule_key))

    context.expiration_eligibility == [true, true, true] and
      match?(
        [%{run_id: run_id, occurrence_number: 1, attempt: 2}]
        when run_id == context.expiration_first_claim.run_id,
        same_schedule_claims
      )
  end

  def behaviour_outcome?(context, :retry_occurrence_rules, _args),
    do:
      context.expiration_retry.occurrence_number ==
        context.expiration_first_claim.occurrence_number and
        context.expiration_retry.attempt == 2

  def behaviour_outcome?(context, expected, args),
    do: IntegrationFamilyChatDriver.behaviour_outcome?(context, expected, args)

  # The setting the page shows: the badge, which the selector's selected option must agree
  # with where a selector is offered.
  defp selected_setting?(view, selector, selected_option, badge) do
    has_element?(view, badge) and
      (not has_element?(view, selector) or has_element?(view, "#{selector} #{selected_option}"))
  end

  defp submit_composer(context, prompt) do
    unless composer_available?(context), do: raise("the chat composer is not available")

    context.view
    |> form("#chat-composer-form[phx-submit=send]", chat: %{prompt: prompt})
    |> render_submit()

    context
  end

  # The test plays Codex: it answers only the newest prompt the LiveView's current session
  # received since the last answer, as the fixture session reported it. The session is the
  # LiveView itself, and its conversation is the one the LiveView opened last, before that
  # prompt.
  defp unanswered_prompt!(context) do
    owner = context.view.pid
    calls = Map.get(context, :codex_calls, []) ++ codex_fixture_calls()
    answered = Map.get(context, :answered_codex_calls, 0)

    owned =
      calls
      |> Enum.with_index()
      |> Enum.filter(fn {{_call, call_owner, _detail}, _index} -> call_owner == owner end)

    prompt = owned |> Enum.filter(&match?({{:prompt, _, _}, _}, &1)) |> List.last()
    open = owned |> Enum.filter(&match?({{:open, _, _}, _}, &1)) |> List.last()

    case {prompt, open} do
      {{{:prompt, _, text}, prompt_index}, {{:open, _, settings}, open_index}}
      when prompt_index >= answered and open_index < prompt_index ->
        {thread_id, model, effort, _mode} = settings

        session = %{
          thread_id: thread_id,
          new_thread_id: "fixture-thread-#{open_index}",
          model: model,
          reasoning_effort: effort
        }

        {text, session,
         Map.merge(context, %{codex_calls: calls, answered_codex_calls: length(calls)})}

      _no_new_prompt ->
        raise "the current Codex session received no new prompt to answer"
    end
  end

  defp codex_fixture_calls(calls \\ []) do
    receive do
      {:codex_fixture_session, call} -> codex_fixture_calls([call | calls])
    after
      0 -> Enum.reverse(calls)
    end
  end

  # Events reach the LiveView from its session, which is the LiveView itself; rendering
  # afterwards waits until it has handled them.
  defp deliver_codex_events(context, events) do
    Enum.each(events, &send(context.view.pid, {:codex, context.view.pid, &1}))
    render(context.view)
    context
  end

  defp await_push_event(_view, "persist-chat") do
    user_id = Process.get(:bnest_behaviour_user_id)
    record = await_central_record(:chat, user_id, 100)
    record["state"]
  end

  defp await_push_event(_view, "clear-chat-storage") do
    user_id = Process.get(:bnest_behaviour_user_id)
    {:ok, %{"state" => %{"messages" => []}}} = Records.read(:chat, user_id)
    %{}
  end

  defp await_push_event(_view, "persist-sifat-allah") do
    user_id = Process.get(:bnest_behaviour_user_id)
    {:ok, record} = SifatAllah.load_progress(user_id)
    # The facade's read is also checked against the raw :sifat_allah record of the owner.
    {:ok, ^record} = Records.read(:sifat_allah, user_id)
    Map.put(record["progress"], "session", record["session"])
  end

  defp await_push_event(view, event) do
    %{proxy: {ref, _topic, _}} = view

    receive do
      {^ref, {:push_event, ^event, payload}} -> payload
    end
  end

  defp await_central_record(type, user_id, attempts) do
    case Records.read(type, user_id) do
      {:ok, record} ->
        record

      {:error, :missing} when attempts > 0 ->
        Process.sleep(10)
        await_central_record(type, user_id, attempts - 1)

      {:error, reason} ->
        raise "central #{type} record unavailable: #{inspect(reason)}"
    end
  end

  @doc false
  def count_storage_ui_visit(_event, _measurements, metadata, visits) do
    if storage_ui_visit?(metadata), do: :counters.add(visits, 1, 1)
    :ok
  end

  defp storage_ui_visit?(%{conn: %Plug.Conn{request_path: "/storage" <> _rest}}), do: true
  defp storage_ui_visit?(%{socket: %{view: BnestAppWeb.StorageLive}}), do: true
  defp storage_ui_visit?(_metadata), do: false

  defp permission_bits(path), do: Bitwise.band(File.stat!(path).mode, 0o777)

  # The `/setup` template for the bootstrap status the store reports. The draft and flash
  # assigns are the ones `LoginLive.mount/3` gives a fresh visit.
  defp render_setup(store) do
    %{
      live_action: :setup,
      setup_status: Bootstrap.status(store),
      setup_draft: [%{username: "", roles: ["admin"]}],
      setup_error: nil,
      flash: %{}
    }
    |> BnestAppWeb.LoginLive.render()
    |> rendered_to_string()
    |> LazyHTML.from_fragment()
  end

  defp sqlite_storage_pointer_path do
    dir = Path.join(System.tmp_dir!(), "bnest-storage-pointer-" <> unique_suffix())
    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(dir) end)
    Path.join(dir, "storage.json")
  end

  defp persist_storage_from_view(context, directory) do
    checked_html =
      context.view
      |> form("form[phx-submit=check_folder]", %{"directory" => directory})
      |> render_submit()

    unless checked_html =~ "Folder looks safe to use." do
      raise "storage folder validation did not succeed"
    end

    context.view
    |> form("form[phx-submit=create_database]", %{"directory" => directory})
    |> render_submit()

    Map.put(context, :requested_directory, directory)
  end

  # A fresh browser that holds only the identity cookie for `token`, opening home.
  defp browser_home(token),
    do: build_conn() |> Plug.Test.put_req_cookie("_bnest_identity", token) |> get("/")

  # Home's protected actions: the chat entry and the logout form.
  defp protected_home?(%{status: 200} = response) do
    page = LazyHTML.from_document(response.resp_body)

    Enum.all?(["[data-role=chat-entry]", "form[action='/logout']"], fn selector ->
      page |> LazyHTML.query(selector) |> Enum.any?()
    end)
  end

  defp protected_home?(_response), do: false

  defp login_redirect?(%{status: 302} = response),
    do: URI.parse(redirected_to(response)).path == "/login"

  defp login_redirect?(_response), do: false

  # Runs `fun` while an isolated trace session records every record operation the calling
  # process makes through the routed repository or a record backend; ConnTest dispatches the
  # request in this process. A probe read must appear first, so an empty result is measured
  # rather than a session that observed nothing. Returns `fun`'s result and the accesses.
  defp record_accesses_during(fun) do
    collector = spawn_link(fn -> collect_record_accesses([]) end)
    session = :trace.session_create(:bnest_behaviour_record_access, collector, [])

    try do
      for module <- [Records, BnestApp.Storage.Ports.RecordBackend] do
        _matched = :trace.function(session, {module, :_, :_}, true, [])
      end

      _traced = :trace.process(session, self(), true, [:call])
      probe = "test-user-trace-probe-" <> unique_suffix()
      _missing = Records.read(:theme, probe)
      result = fun.()
      _traced = :trace.process(session, self(), false, [:call])
      delivered = :trace.delivered(session, self())

      receive do
        {:trace_delivered, _process, ^delivered} -> :ok
      end

      send(collector, {:report, self()})

      receive do
        {:record_accesses, [{Records, :read, [:theme, ^probe]} | accesses]} ->
          {result, accesses}

        {:record_accesses, accesses} ->
          raise "record trace missed its probe: #{inspect(accesses)}"
      end
    after
      :trace.session_destroy(session)
    end
  end

  defp collect_record_accesses(accesses) do
    receive do
      {:trace, _process, :call, {module, operation, arguments}}
      when operation in @record_operations ->
        collect_record_accesses([{module, operation, arguments} | accesses])

      {:trace, _process, :call, _other} ->
        collect_record_accesses(accesses)

      {:report, caller} ->
        send(caller, {:record_accesses, Enum.reverse(accesses)})
    end
  end

  defp unique_suffix, do: Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
  defp username_suffix, do: Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)

  defp sqlite_migrations_path, do: Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")

  defp sqlite_repo_started!(database_path) do
    :ok = SqliteCoordinator.ensure_started!(database_path)
    SqliteRepo
  end

  defp seed_flat_fixtures!(root) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    user_id = "user-" <> unique_suffix()
    username = "test-user-sqlite-" <> username_suffix()
    password = "Synthetic SQLite Password 123!"
    {:ok, verifier} = Argon2CredentialHasher.hash(password)

    account = %{
      "schemaVersion" => 1,
      "recordType" => "account",
      "userId" => user_id,
      "displayUsername" => username,
      "normalizedUsername" => username,
      "roles" => ["admin"],
      "passwordVerifier" => verifier,
      "createdAt" => now
    }

    index = %{
      "schemaVersion" => 1,
      "recordType" => "username-index",
      "normalizedUsername" => username,
      "userId" => user_id
    }

    write_fixture!(root, "system/bootstrap.json", %{
      "schemaVersion" => 1,
      "recordType" => "bootstrap",
      "state" => "closed",
      "attemptId" => "attempt-" <> unique_suffix(),
      "startedAt" => now,
      "closedAt" => now,
      "accounts" => [
        %{
          "userId" => user_id,
          "normalizedUsername" => username,
          "accountSha256" => digest(account),
          "indexSha256" => digest(index)
        }
      ]
    })

    write_fixture!(root, "system/accounts/#{user_id}.json", account)
    write_fixture!(root, "system/usernames/#{username}.json", index)

    write_fixture!(root, "users/#{user_id}/preferences/theme.json", %{
      "schemaVersion" => 1,
      "recordType" => "theme-preference",
      "ownerId" => user_id,
      "sourceImportId" => nil,
      "revision" => 0,
      "theme" => "dark",
      "updatedAt" => now
    })

    %{user_id: user_id, username: username, password: password}
  end

  # Chat and learning records as a browser import normalizes them, written as flat files
  # beside the theme `seed_flat_fixtures!/1` wrote. Returns every journey record by type.
  defp seed_journey_records!(root, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    [
      chat: {chat_source(), "chat/current.json"},
      sifat_allah: {learning_source(), "sifat-allah/progress.json"}
    ]
    |> Map.new(fn {type, {source, relative}} ->
      {:ok, ^type, candidate} =
        Normalizer.normalize(
          source["storageArea"],
          source["storageKey"],
          source["payload"],
          "import-journey-fixture",
          now,
          Storage.record_kinds()
        )

      record = Map.merge(candidate, %{"ownerId" => user_id, "revision" => 0})
      write_fixture!(root, "users/#{user_id}/#{relative}", record)
      {type, record}
    end)
    |> Map.put(
      :theme,
      root
      |> Path.join("users/#{user_id}/preferences/theme.json")
      |> File.read!()
      |> Jason.decode!()
    )
  end

  defp digest(record),
    do: :crypto.hash(:sha256, Jason.encode!(record)) |> Base.encode16(case: :lower)

  defp write_fixture!(root, relative_path, record) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(record))
  end

  defp roles_for(:child), do: ["children"]
  defp roles_for(:child_admin), do: ["children", "admin"]
  defp roles_for(:parent), do: ["parents"]
  defp roles_for(_role), do: ["admin"]

  defp answer_position(view, correct_answer) do
    Enum.find_index(1..4, fn index ->
      has_element?(view, ".sifat-answer-grid button:nth-child(#{index})", correct_answer)
    end)
  end

  defp effort_label("xhigh"), do: "XHigh"
  defp effort_label(effort), do: String.capitalize(effort)

  defp import_envelope_count(store, owner_id) do
    store.root
    |> Path.join("users/#{owner_id}/imports/*.json")
    |> Path.wildcard()
    |> length()
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
      "payload" => Jason.encode!(Map.put(Quiz.progress(), "session", %{"mode" => "dashboard"}))
    }
  end

  defp theme_source,
    do: %{"storageArea" => "localStorage", "storageKey" => "phx:theme", "payload" => "dark"}

  defp prepare_default_backup(context) do
    context = prepare_backup_destination(context)
    repository = Path.join(context.backup_fixture_root, "repository")
    File.mkdir_p!(repository)
    File.write!(Path.join(repository, ".gitignore"), "/data/*\n")
    {_output, 0} = System.cmd("git", ["init", "--quiet", repository])
    :ok = TestBackupDestination.use_repository_root!(repository)

    Map.put(context, :default_backup_directory, Path.join(repository, "data/backup"))
  end

  defp prepare_backup_destination(context) do
    ensure_scheduler_storage()
    {temporary_root, 0} = System.cmd("realpath", [System.tmp_dir!()])
    root = Path.join(String.trim(temporary_root), "bnest-behaviour-backup-" <> unique_suffix())
    backup_directory = Path.join(root, "destination")
    config_path = Path.join(root, "configuration/backup.json")
    previous = System.get_env("BNEST_BACKUP_CONFIG")
    System.put_env("BNEST_BACKUP_CONFIG", config_path)

    ExUnit.Callbacks.on_exit(fn ->
      restore_environment("BNEST_BACKUP_CONFIG", previous)
      File.rm_rf(root)
    end)

    Map.merge(context, %{
      backup_config_path: config_path,
      backup_directory: backup_directory,
      backup_fixture_root: root
    })
  end

  # Copies the storage pointer the run resolves (or, while none is saved, the one its
  # default resolves to) to a private test-run path and points Storage at it for the
  # scenario, so the copy names the same database and phase and a write cannot reach the
  # run's own pointer.
  defp isolated_storage_pointer! do
    runtime = TestRuntimeRoot.create!("admin-allowlists")
    pointer = Path.join(runtime.path, "pointer/storage.json")
    resolved = FileConfigStore.resolved_database_path()

    document =
      case FileConfigStore.read() do
        {:ok, config} ->
          config

        {:error, _absent_or_invalid} ->
          %{
            "schemaVersion" => 1,
            "databaseDirectory" => Path.dirname(resolved),
            "databaseFilename" => Path.basename(resolved),
            "phase" => "flat_primary",
            "migrationId" => "flat-files-v1-to-sqlite-v1"
          }
      end

    File.mkdir_p!(Path.dirname(pointer))
    File.write!(pointer, Jason.encode!(document))
    previous = System.get_env("BNEST_STORAGE_CONFIG")
    System.put_env("BNEST_STORAGE_CONFIG", pointer)

    ExUnit.Callbacks.on_exit(fn ->
      restore_environment("BNEST_STORAGE_CONFIG", previous)
      TestRuntimeRoot.cleanup!(runtime)
    end)

    pointer
  end

  defp schedule_row(page, group_title_id, schedule_key),
    do:
      LazyHTML.query(
        page,
        ~s(section[aria-labelledby="#{group_title_id}"] .schedule-row[data-schedule-key="#{schedule_key}"])
      )

  defp rendered_panels(body) do
    body
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("a.admin-settings-panel")
    |> Enum.map(fn panel ->
      %{
        href: panel |> LazyHTML.attribute("href") |> List.first(),
        label: panel |> LazyHTML.query("strong") |> LazyHTML.text(),
        owner: panel |> LazyHTML.attribute("data-config-owner") |> List.first(),
        fields: panel |> LazyHTML.attribute("data-editable-fields") |> List.first()
      }
    end)
  end

  # Storage lists no editable field: once a location is chosen, its facade refuses to save
  # another, and the pointer file keeps its bytes.
  defp owner_saves_only_allowlisted?(context, %{owner: "BnestApp.Storage", fields: ""}) do
    before = File.read!(context.storage_pointer)
    elsewhere = Path.join(Path.dirname(context.storage_pointer), "elsewhere")
    refused = Storage.persist_directory(elsewhere)

    refused == {:error, :immutable} and File.read!(context.storage_pointer) == before and
      not File.exists?(elsewhere)
  end

  # Backup lists the destination and the backup schedule's `enabled` and `daily_time_wib`.
  # A schedule save carrying only unlisted fields is refused and changes nothing; one that
  # also carries the listed fields changes only what they and the save itself decide. An
  # unsafe destination is refused before anything is written.
  defp owner_saves_only_allowlisted?(context, %{
         owner: "BnestApp.Backup",
         fields: "destination_directory,enabled,daily_time_wib"
       }) do
    key = context.allowlist_schedule_key
    before = Scheduler.get_schedule(key)
    revision = %{"revision" => Integer.to_string(before.revision)}

    unlisted =
      Scheduler.update_daily(key, Map.merge(@unlisted_schedule_fields, revision), @behaviour_now)

    after_unlisted = Scheduler.get_schedule(key)

    listed =
      Map.merge(@unlisted_schedule_fields, %{
        "daily_time_wib" => "03:30",
        "enabled" => "false",
        "revision" => revision["revision"]
      })

    saved = Scheduler.update_daily(key, listed, @behaviour_now)
    after_saved = Scheduler.get_schedule(key)
    destination = Backup.save_destination("test-user-relative/backup")

    match?({:error, _reason}, unlisted) and after_unlisted == before and
      match?({:ok, _schedule}, saved) and
      Map.drop(after_saved, @saved_schedule_columns) == Map.drop(before, @saved_schedule_columns) and
      after_saved.daily_at_utc == "20:30" and after_saved.enabled == false and
      destination == {:error, :not_absolute} and not File.exists?(context.backup_config_path)
  end

  defp owner_saves_only_allowlisted?(_context, _panel_without_proof), do: false

  defp restore_environment(name, nil), do: System.delete_env(name)
  defp restore_environment(name, value), do: System.put_env(name, value)
  defp schedule_key(prefix), do: "bdd-#{prefix}-#{unique_suffix()}"

  defp ensure_scheduler_storage do
    :ok = SqliteCoordinator.ensure_started!(FileConfigStore.resolved_database_path())
    :ok = PersistentSchedules.apply_and_verify!(@behaviour_now)
  end

  # Has the application's running coordinator reconcile once at `now` instead of the wall
  # clock, so it claims only what is due by then, and without its tick handlers: the push
  # dispatch they run repoints the shared SQLite repository at Family Chat's database
  # (see `BnestApp.Scheduler`'s `run_tick_handlers/0` comment). Both are restored after.
  defp reconcile_at(now) do
    coordinator = Process.whereis(Scheduler)
    %{clock: clock} = :sys.get_state(coordinator)
    configuration = Application.fetch_env!(:bnest_app, Scheduler)
    :sys.replace_state(coordinator, &Map.put(&1, :clock, fn -> now end))
    Application.put_env(:bnest_app, Scheduler, Keyword.put(configuration, :tick_handlers, []))

    try do
      :ok = Scheduler.reconcile()
    after
      Application.put_env(:bnest_app, Scheduler, configuration)
      :sys.replace_state(coordinator, &Map.put(&1, :clock, clock))
    end
  end

  defp await_scheduler_restart(_supervisor, _old_scheduler, 0),
    do: raise("scheduler did not restart")

  defp await_scheduler_restart(supervisor, old_scheduler, attempts) do
    scheduler = Process.whereis(BnestApp.Scheduler)

    if is_pid(supervisor) and is_pid(scheduler) and scheduler != old_scheduler do
      scheduler
    else
      Process.sleep(10)
      await_scheduler_restart(supervisor, old_scheduler, attempts - 1)
    end
  end
end
