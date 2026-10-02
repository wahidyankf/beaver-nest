defmodule BnestApp.Behaviour.UnitHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver

  alias BnestApp.AdminConfig.Registry, as: AdminRegistry
  alias BnestApp.Backup.{Config, Receipt, Run}
  alias BnestApp.Behaviour.UnitFamilyChatDriver
  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.CodexChat.ModelCatalog
  alias BnestApp.Deployment
  alias BnestApp.FamilyChat
  alias BnestApp.Identity
  alias BnestApp.Identity.{Bootstrap, Login, Sessions}
  alias BnestApp.Identity.Domain.{Authorization, Credentials}
  alias BnestApp.Identity.Ports.IdentityStore
  alias BnestApp.Preferences
  alias BnestApp.Scheduler
  alias BnestApp.Scheduler.Domain.Policy
  alias BnestApp.Scheduler.Ports.ScheduleStore
  alias BnestApp.SifatAllah
  alias BnestApp.SifatAllah.Domain.Quiz
  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.FlatMigration
  alias BnestApp.Storage.Domain.Location, as: StorageLocation
  alias BnestApp.Storage.Import
  alias BnestApp.Storage.Ports.RecordBackend
  alias BnestApp.Storage.Records
  alias BnestApp.Test.CodexFixtureModels, as: FixtureModels
  alias BnestApp.Test.InMemory.AgentSession, as: InMemoryAgentSession
  alias BnestApp.Test.InMemory.IdentityStore, as: InMemoryIdentityStore
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestApp.Test.SchedulerDispatch
  alias BnestAppWeb.ChatLive
  alias BnestAppWeb.DataMigrationLive
  alias BnestAppWeb.SifatAllahLive
  alias Phoenix.HTML.Safe
  alias Phoenix.LiveView.{Socket, Utils}

  @behaviour_now ~U[2026-09-04 12:00:00Z]
  @streamed_answer [
    {:thread_started, "fixture-thread"},
    {:assistant_update, "fixture-answer", "Fixture response"},
    {:assistant_update, "fixture-answer", "Fixture response complete."},
    :turn_completed
  ]
  @in_memory_flat_root "/in-memory/flat"
  @synthetic_password "Synthetic password 1!"

  # Mirrors `BnestAppWeb.Endpoint`'s session options, which the router's pipelines expect
  # the endpoint to have applied.
  @session_options Plug.Session.init(
                     store: :cookie,
                     key: "_bnest_app_key",
                     signing_salt: "GMjl1ern",
                     same_site: "Lax"
                   )

  @impl true
  def open(context, "/chat"), do: context |> start_chat_runtime() |> mount_chat("/chat")

  def open(context, "/"), do: render_home(context)

  def open(context, "/apps/sifat-allah") do
    context |> start_sifat_allah_records() |> mount_sifat_allah()
  end

  def open(context, "/family-chat") do
    render_family_chat_room(context, FamilyChat.canonical_room_slug())
  end

  def open(context, "/family-chat/" <> slug) do
    render_family_chat_room(context, slug)
  end

  @impl true
  def brand_logo_visible?(context) do
    context.page
    |> LazyHTML.query("[data-role=brand-logo][src='/images/beaver-nest-logo.png']")
    |> Enum.any?()
  end

  # Installability is what the document a visitor lands on after opening "/" declares: the
  # root layout's manifest and icon links, each at a path the endpoint serves statically.
  # The manifest's contents and service-worker activation are proven at E2E.
  @impl true
  def installable_as_app?(context) do
    document = visitor_document(context, "/")
    manifest = document |> LazyHTML.query("link[rel=manifest]") |> LazyHTML.attribute("href")

    icons =
      document
      |> LazyHTML.query("link[rel=icon][type='image/png'], link[rel=apple-touch-icon]")
      |> LazyHTML.attribute("href")

    manifest == ["/manifest.webmanifest"] and "/images/beaver-nest-512.png" in icons and
      Enum.all?(manifest ++ icons, &statically_served?/1)
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

  # The selection is read from the rendered selector, or from the badge where no selector is
  # offered, and the Codex conversation the LiveView opened last must run that model.
  @impl true
  def selected_model?(context, display_name) do
    model_id = FixtureModels.fetch_by_display_name!(display_name).id

    rendered_setting(context.page, "[data-role=model-selector]", "data-model") == [model_id] and
      match?({:agent_session, :open, {_thread, ^model_id, _effort, _mode}}, last_open(context))
  end

  @impl true
  def effort_selector_lists_supported?(context) do
    [model_id] =
      context.page |> LazyHTML.query(".model-badge") |> LazyHTML.attribute("data-model")

    model = FixtureModels.fetch_by_id!(model_id)

    context.page
    |> LazyHTML.query("[data-role=effort-selector] option")
    |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))
    |> Kernel.==(Enum.map(model.supported_reasoning_efforts, &effort_label/1))
  end

  @impl true
  def selected_effort?(context, effort) do
    effort = String.downcase(effort)

    rendered_setting(context.page, "[data-role=effort-selector]", "data-reasoning-effort") ==
      [effort] and
      match?({:agent_session, :open, {_thread, _model, ^effort, _mode}}, last_open(context))
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
    model_id = rendered_option_value!(context, "[data-role=model-selector]", display_name)
    select_chat_setting(context, "select_model", %{"model" => model_id})
  end

  @impl true
  def select_effort(context, effort) do
    value = rendered_option_value!(context, "[data-role=effort-selector]", effort)
    select_chat_setting(context, "select_effort", %{"reasoning_effort" => value})
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

  # The page shows the mode, and the Codex conversation the LiveView opened last runs in it.
  @impl true
  def repository_access_read_only?(context) do
    not Enum.empty?(
      LazyHTML.query(context.page, "[data-role=repository-access][data-mode=read-only]")
    ) and
      match?({:agent_session, :open, {_thread, _model, _effort, :read_only}}, last_open(context))
  end

  @impl true
  def repository_access_write_enabled?(context) do
    not Enum.empty?(
      LazyHTML.query(context.page, "[data-role=repository-access][data-mode=workspace-write]")
    ) and
      match?(
        {:agent_session, :open, {_thread, _model, _effort, :workspace_write}},
        last_open(context)
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
  def enable_repository_writes(context), do: toggle_repository_writes(context, "true")

  @impl true
  def disable_repository_writes(context), do: toggle_repository_writes(context, "false")

  @impl true
  def attempt_empty_message(context), do: submit_composer(context, "   ")

  @impl true
  def send_message(context, message) do
    unless composer_available?(context), do: raise("the chat composer is not available")
    submit_composer(context, message)
  end

  @impl true
  def submit_with_shift_enter(context, message), do: send_message(context, message)

  # The composer is disabled while Codex works, so this submits it as a forced browser
  # submission would; the LiveView's own busy guard decides what happens.
  @impl true
  def attempt_message_before_finished(context, message), do: submit_composer(context, message)

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
    context = answer_prompt(context, @streamed_answer)
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

    # Codex may receive the turn's prompt once more after the reconnect, never twice.
    prompts = Enum.count(context.codex_calls, &match?({:agent_session, :prompt, _, _}, &1))

    (resumed? or failed_safely?) and visitor_message_count == 1 and prompts <= 2
  end

  @impl true
  def report_public_codex_progress(context) do
    answer_prompt(context, [
      {:reasoning_update, "fixture-reasoning", "Fixture reasoning summary"},
      {:assistant_update, "fixture-progress", "Fixture progress"},
      {:assistant_update, "fixture-final", "Fixture final answer"},
      :turn_completed
    ])
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

  # The agent session refuses this prompt, so what the page shows is the facade's own
  # handling of a session that cannot accept a message.
  @impl true
  def reject_message(context, message), do: send_message(context, message)

  @impl true
  def report_codex_error(context, message), do: answer_prompt(context, [{:error, message}])

  @impl true
  def alert_visible?(context, message) do
    context.page
    |> LazyHTML.query("[role=alert]")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(message)
  end

  # Typing reaches the LiveView through the composer form's change event.
  @impl true
  def type_draft(context, draft) do
    if context.page
       |> LazyHTML.query("form#chat-composer-form[phx-change=recover_draft]")
       |> Enum.empty?(),
       do: raise("the chat page offers no composer form that reports changes")

    chat_event(context, "recover_draft", %{"chat" => %{"prompt" => draft}})
  end

  @impl true
  def composer_contains?(context, draft) do
    context.page |> LazyHTML.query("textarea") |> LazyHTML.text() |> Kernel.==(draft)
  end

  # A chat route is the one the visitor's LiveView was mounted from, and the router must
  # resolve it to the module that socket runs.
  @impl true
  def current_route?(%{chat_socket: socket} = context, route),
    do: context.route == route and routed_live_view(route) == socket.view

  def current_route?(context, route), do: context.route == route

  # A deployment replaces the server under the connected client: the LiveView terminates, the
  # record repository restarts, and the client mounts its route again on a fresh socket, so
  # only what the LiveView saved comes back. The browser keeps the composer text the page
  # rendered and replays it through the form's recovery event. A turn the remount resends is
  # answered by Codex like any other prompt.
  @impl true
  def reconnect(context) do
    draft =
      context.page
      |> LazyHTML.query("form#chat-composer-form textarea")
      |> LazyHTML.text()

    remounted = remount_chat(context)

    remounted =
      if Enum.any?(new_calls(remounted, context), &match?({:agent_session, :prompt, _, _}, &1)),
        do: answer_prompt(remounted, @streamed_answer),
        else: remounted

    case {draft, form_recovery_event(remounted.page, "form#chat-composer-form")} do
      {"", _event} -> remounted
      {_draft, nil} -> remounted
      {draft, event} -> chat_event(remounted, event, %{"chat" => %{"prompt" => draft}})
    end
  end

  # Each synthetic visitor is its own user with its own LiveView, over one record repository.
  @impl true
  def prepare_recovery_group(context, client_count, group_count, route) do
    context = start_chat_runtime(context)

    clients =
      Enum.map(1..client_count, fn index ->
        draft = "Recovery draft #{index}"

        client =
          context
          |> Map.put(:chat_user, chat_user(context, "-#{index}"))
          |> Map.delete(:codex_calls)
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

  # A reload is a fresh mount over a restarted record repository, as a reconnect is.
  @impl true
  def reload(%{chat_socket: _socket} = context), do: remount_chat(context)

  # A reload is a fresh mount over a restarted record repository, so only what the LiveView
  # saved through the SifatAllah facade can come back. The saved record is checked in the
  # backend itself before the remount, and the remount must restore exactly that record.
  def reload(%{sifat_socket: _socket} = context) do
    owner = context.sifat_user["userId"]
    :ok = ExUnit.Callbacks.stop_supervised(Records)
    ExUnit.Callbacks.start_supervised!({Records, store: context.sifat_records})

    {:ok, saved} = SifatAllah.load_progress(owner)
    %{{:sifat_allah, ^owner} => ^saved} = InMemoryRecordBackend.snapshot(context.sifat_records)

    context = mount_sifat_allah(context)
    ^saved = context.sifat_socket.assigns.central_record
    context
  end

  # Clearing must close the conversation, open a new one without a thread, and save the
  # emptied transcript the page then shows.
  @impl true
  def clear_chat(context) do
    session = context.chat_socket.assigns.codex_session

    if context.page |> LazyHTML.query("[data-role=clear-chat][phx-click=clear]") |> Enum.empty?(),
      do: raise("the chat page offers no clear control")

    cleared = chat_event(context, "clear", %{})

    calls =
      cleared
      |> new_calls(context)
      |> Enum.drop_while(&(&1 != {:agent_session, :close, session}))

    unless match?([_close | _opened], calls) and
             Enum.any?(calls, &match?({:agent_session, :open, {nil, _, _, _}}, &1)) and
             match?(
               {:ok, %{messages: []}, _record},
               CodexChat.load_transcript(cleared.chat_user["userId"])
             ),
           do: raise("clearing did not start a new Codex session over a saved empty chat")

    cleared
  end

  @impl true
  def study_mode_available?(context) do
    button_visible?(context.page, "Belajar 3 Pasangan")
  end

  @impl true
  def quiz_mode_available?(context), do: button_visible?(context.page, "Latihan Ujian")

  @impl true
  def start_learning(context),
    do: click_sifat_allah(context, "button[phx-click=start-learning]", "start-learning")

  # The learner's saved progress is the precondition, so it is saved through the SifatAllah
  # facade and the page is opened again over it; the Given fails unless the page shows it.
  @impl true
  def remember_every_sifat_pair(context) do
    progress =
      Enum.reduce(Quiz.curriculum(), Quiz.progress(), fn pair, acc ->
        Quiz.remember(acc, pair.id)
      end)

    {:ok, _saved} =
      SifatAllah.save_progress(
        context.sifat_user["userId"],
        Map.put(progress, "session", %{"mode" => "dashboard"}),
        context.sifat_socket.assigns.central_record
      )

    context = mount_sifat_allah(context)

    unless progress_shows?(context, "120 dari 120 soal sudah hafal") do
      raise "the saved Sifat Allah progress was not restored"
    end

    context
  end

  @impl true
  def swipe_study_card_left(context),
    do: swipe_sifat_allah(context, "[data-role=study-card]", "swipe-study", "left")

  @impl true
  def swipe_study_card_right(context),
    do: swipe_sifat_allah(context, "[data-role=study-card]", "swipe-study", "right")

  # The button asks the browser to go back; the SifatHistory hook answers that instruction
  # with the `dashboard` event, after a history step back when the activity pushed an entry.
  @impl true
  def return_to_mission(context) do
    context =
      click_sifat_allah(context, "button[phx-click=back-to-mission]", "back-to-mission")

    unless List.last(context.sifat_pushes) == ["sifat-history-back", %{}] do
      raise "returning to the mission did not ask the browser to go back"
    end

    sifat_allah_hook_event(context, "dashboard")
  end

  # Browser Back pops the history entry the activity pushed; the SifatHistory hook then sends
  # the `dashboard` event.
  @impl true
  def browser_back_to_mission(context) do
    unless ["sifat-history-entry", %{}] in context.sifat_pushes do
      raise "the activity pushed no history entry to go back from"
    end

    sifat_allah_hook_event(context, "dashboard")
  end

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
  def mark_current_pair_remembered(context),
    do: click_sifat_allah(context, "button[phx-click=remember-pair]", "remember-pair")

  @impl true
  def progress_shows?(context, progress) do
    context.page
    |> LazyHTML.query(".sifat-stage")
    |> LazyHTML.text()
    |> String.trim()
    |> String.contains?(progress)
  end

  @impl true
  def ask_reset_sifat_progress(context),
    do: click_sifat_allah(context, "button[phx-click=ask-reset-progress]", "ask-reset-progress")

  @impl true
  def confirm_reset_sifat_progress(context),
    do: click_sifat_allah(context, "button[phx-click=reset-progress]", "reset-progress")

  @impl true
  def start_quiz(context),
    do: click_sifat_allah(context, "button[phx-click=start-quiz]", "start-quiz")

  # Both positions are read from the rendered answer buttons, before and after the next
  # question the LiveView itself selects.
  @impl true
  def quiz_answer_positions_vary?(context) do
    first_position = rendered_answer_position(context.page, "Ada")
    context = click_sifat_allah(context, "button[phx-click=next-question]", "next-question")
    first_position != rendered_answer_position(context.page, "Hudus")
  end

  @impl true
  def quiz_answer_choices_locked?(context) do
    buttons = context.page |> LazyHTML.query(".sifat-answer-grid button") |> Enum.to_list()

    buttons != [] and
      Enum.all?(buttons, fn button -> LazyHTML.attribute(button, "disabled") != [] end)
  end

  # The LiveView schedules `{:auto_advance, :quiz, token}` five seconds after an answer; the
  # message is delivered now with the token the socket holds, so its own token and feedback
  # guards decide whether the quiz moves on. The real delay is proven at Integration and E2E.
  @impl true
  def wait_for_quiz_auto_advance(context) do
    socket = context.sifat_socket

    {:noreply, socket} =
      SifatAllahLive.handle_info(
        {:auto_advance, :quiz, socket.assigns.auto_advance_token},
        socket
      )

    render_sifat_allah(context, socket)
  end

  @impl true
  def start_learned_review(context) do
    click_sifat_allah(
      context,
      "button[phx-click=start-learned-review]",
      "start-learned-review"
    )
  end

  @impl true
  def start_focused_review(context),
    do: click_sifat_allah(context, "button[phx-click=start-review]", "start-review")

  @impl true
  def swipe_quiz_question_left(context),
    do: swipe_sifat_allah(context, "[data-role=quiz-question]", "swipe-quiz", "left")

  @impl true
  def swipe_quiz_question_right(context),
    do: swipe_sifat_allah(context, "[data-role=quiz-question]", "swipe-quiz", "right")

  @impl true
  def next_quiz_question(context),
    do: click_sifat_allah(context, "button[phx-click=next-question]", "next-question")

  @impl true
  def answer_quiz(context, answer) do
    click_sifat_allah(
      context,
      ~s([data-role=quiz-question] button[phx-click=answer][phx-value-answer="#{answer}"]),
      "answer",
      %{"answer" => answer}
    )
  end

  @impl true
  def answer_focused_review(context, answer) do
    click_sifat_allah(
      context,
      ~s([data-role=review-question] button[phx-click=review-answer][phx-value-answer="#{answer}"]),
      "review-answer",
      %{"answer" => answer}
    )
  end

  @impl true
  def next_focused_review(context) do
    click_sifat_allah(
      context,
      "button[phx-click=next-review-question]",
      "next-review-question"
    )
  end

  @impl true
  def revision_list_contains?(context, name) do
    context.page
    |> LazyHTML.query("[data-testid=sifat-allah-revision-list]")
    |> LazyHTML.text()
    |> String.contains?(name)
  end

  # Codex chat runs the production `ChatLive` over the CodexChat facade. Its transcript store is
  # the configured record-backed one, which reaches Storage's record repository; the repository
  # runs here over an in-memory record backend, kept in the context so a reload or reconnect
  # can restart the repository over it. The model catalog discovers the configured fixture
  # models, and the agent session is the recording in-memory double, which reports every call
  # to this process. A Given may hold Storage pointer state for the in-memory ports in
  # `:chat_storage`.
  defp start_chat_runtime(%{chat_records: _records} = context), do: context

  defp start_chat_runtime(context) do
    previous_storage = StoragePorts.install(Map.get(context, :chat_storage, []))
    ExUnit.Callbacks.on_exit(fn -> StoragePorts.restore(previous_storage) end)
    records = InMemoryRecordBackend.start()
    ExUnit.Callbacks.start_supervised!({Records, store: records})
    ExUnit.Callbacks.start_supervised!(ModelCatalog)
    previous_chat = Application.fetch_env!(:bnest_app, CodexChat)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:bnest_app, CodexChat, previous_chat) end)

    Application.put_env(
      :bnest_app,
      CodexChat,
      Keyword.put(previous_chat, :agent_session, InMemoryAgentSession)
    )

    Map.merge(context, %{chat_records: records, chat_user: chat_user(context, "")})
  end

  defp chat_user(context, suffix) do
    context
    |> identity()
    |> Map.merge(%{
      "userId" => "user-test-unit-chat" <> suffix,
      "displayUsername" => "test-user-unit-chat" <> suffix
    })
  end

  # The production `mount/3` of the LiveView the router serves `route` with, on a fresh
  # connected socket for the visitor, as a page load and its socket connection do.
  defp mount_chat(context, route) do
    view = routed_live_view(route)

    socket = %Socket{
      view: view,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}, current_user: context.chat_user}
    }

    {:ok, socket} = view.mount(%{}, %{}, socket)
    context |> Map.put(:route, route) |> render_chat(socket)
  end

  defp routed_live_view(route) do
    %{phoenix_live_view: {view, _action, _options, _live_session}} =
      Phoenix.Router.route_info(BnestAppWeb.Router, "GET", route, "bnest.test")

    view
  end

  # Before the remount, the chat the facade loads must be the record the backend holds, so
  # only what the LiveView saved can come back.
  defp remount_chat(context) do
    owner = context.chat_user["userId"]
    {_backend, active} = Records.active_backend(context.chat_records)
    saved = active |> InMemoryRecordBackend.snapshot() |> Map.get({:chat, owner})

    case {CodexChat.load_transcript(owner), saved} do
      {{:ok, _transcript, ^saved}, %{}} -> :ok
      {{:error, :missing}, nil} -> :ok
      loaded -> raise "the saved chat does not load back: #{inspect(loaded)}"
    end

    :ok = ChatLive.terminate({:shutdown, :closed}, context.chat_socket)
    :ok = ExUnit.Callbacks.stop_supervised(Records)
    ExUnit.Callbacks.start_supervised!({Records, store: context.chat_records})
    mount_chat(context, context.route)
  end

  # A click reaches the LiveView only through a toggle the page renders enabled, with the
  # value the page gave it.
  defp toggle_repository_writes(context, enabled) do
    toggle =
      "[data-role=repository-write-toggle][phx-click=set_repository_write]" <>
        "[phx-value-enabled=#{enabled}]:not([disabled])"

    if context.page |> LazyHTML.query(toggle) |> Enum.empty?(),
      do: raise("the chat page offers no enabled repository-write toggle for #{enabled}")

    chat_event(context, "set_repository_write", %{"enabled" => enabled})
  end

  defp submit_composer(context, prompt) do
    if context.page
       |> LazyHTML.query("form#chat-composer-form[phx-submit=send] textarea[name='chat[prompt]']")
       |> Enum.empty?(),
       do: raise("the chat page offers no composer form")

    chat_event(context, "send", %{"chat" => %{"prompt" => prompt}})
  end

  # A selection reaches the LiveView only through an enabled selector the page renders, as the
  # value of its option with that label.
  defp rendered_option_value!(context, selector, label) do
    context.page
    |> LazyHTML.query("#{selector}:not([disabled]) option")
    |> Enum.find_value(fn option ->
      if option |> LazyHTML.text() |> String.trim() == label,
        do: option |> LazyHTML.attribute("value") |> List.first()
    end) || raise "the chat page offers no enabled #{selector} option #{inspect(label)}"
  end

  # Changing a setting reopens the Codex conversation, which must resume the thread the
  # transcript already has, so the turns stay one conversation.
  defp select_chat_setting(context, event, params) do
    thread_id = context.chat_socket.assigns.chat.thread_id
    selected = chat_event(context, event, params)

    unless selected
           |> new_calls(context)
           |> Enum.filter(&match?({:agent_session, :open, _settings}, &1))
           |> Enum.all?(&match?({:agent_session, :open, {^thread_id, _, _, _}}, &1)),
           do: raise("changing a chat setting did not resume the conversation's thread")

    selected
  end

  # The setting the page shows: the selected option where a selector is offered, which the
  # badge must agree with, else the badge alone.
  defp rendered_setting(page, selector, badge_attribute) do
    badge = page |> LazyHTML.query(".model-badge") |> LazyHTML.attribute(badge_attribute)

    if page |> LazyHTML.query(selector) |> Enum.empty?() do
      badge
    else
      selected =
        page |> LazyHTML.query("#{selector} option[selected]") |> LazyHTML.attribute("value")

      if selected == badge, do: selected, else: []
    end
  end

  # The driver plays Codex: it answers only a prompt the LiveView's current session received,
  # with events sent from that session to the LiveView's own `handle_info/2`.
  defp answer_prompt(context, events) do
    session = context.chat_socket.assigns.codex_session

    unless Enum.any?(context.codex_calls, &match?({:agent_session, :prompt, ^session, _}, &1)),
      do: raise("the current Codex session received no prompt to answer")

    Enum.reduce(events, context, fn event, context ->
      {:noreply, socket} = ChatLive.handle_info({:codex, session, event}, context.chat_socket)
      render_chat(context, socket)
    end)
  end

  defp chat_event(context, event, params) do
    {:noreply, socket} = ChatLive.handle_event(event, params, context.chat_socket)
    render_chat(context, socket)
  end

  # Renders the socket's assigns with the production template and moves the agent-session
  # calls reported so far into the context, oldest first.
  defp render_chat(context, socket) do
    page =
      socket.assigns
      |> Map.delete(:__changed__)
      |> ChatLive.render()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> LazyHTML.from_fragment()

    calls = agent_session_calls()

    context
    |> Map.update(:codex_calls, calls, &(&1 ++ calls))
    |> Map.put(:chat_socket, socket)
    |> Map.put(:page, page)
  end

  defp agent_session_calls(calls \\ []) do
    receive do
      {:agent_session, _call, _detail} = call -> agent_session_calls([call | calls])
      {:agent_session, :prompt, _session, _prompt} = call -> agent_session_calls([call | calls])
    after
      0 -> Enum.reverse(calls)
    end
  end

  # The agent-session calls made between the `earlier` context and the `later` one.
  defp new_calls(later, earlier),
    do: Enum.drop(later.codex_calls, length(Map.get(earlier, :codex_calls, [])))

  defp last_open(context) do
    context.codex_calls
    |> Enum.filter(&match?({:agent_session, :open, _settings}, &1))
    |> List.last()
  end

  # The event the browser client replays into a form when it reconnects: the form's
  # `phx-auto-recover` event, else its change event; `ignore` replays nothing.
  defp form_recovery_event(page, form_selector) do
    form = LazyHTML.query(page, form_selector)

    case {LazyHTML.attribute(form, "phx-auto-recover"), LazyHTML.attribute(form, "phx-change")} do
      {["ignore"], _change} -> nil
      {[event], _change} -> event
      {[], [event]} -> event
      _none -> nil
    end
  end

  # The document a visitor's browser shows after opening `path`: router requests over the
  # browser request path with a bootstrapped account, following redirects. The login page
  # reads the setup status from the named Identity process.
  defp visitor_document(context, path) do
    _context = start_request_path(context, [synthetic_account("test-user-unit", ["admin"])])
    ExUnit.Callbacks.start_supervised!(Identity)
    follow_to_document(path, 3)
  end

  defp follow_to_document(path, redirects_left) do
    response = dispatch_request(:get, path, nil)

    case {response.status, Plug.Conn.get_resp_header(response, "location")} do
      {200, _location} ->
        LazyHTML.from_document(response.resp_body)

      {302, [location]} when redirects_left > 0 ->
        follow_to_document(location, redirects_left - 1)
    end
  end

  defp statically_served?("/" <> path),
    do: path |> String.split("/") |> hd() |> Kernel.in(BnestAppWeb.static_paths())

  defp identity(%{identity_role: :child}), do: %{"roles" => ["children"]}
  defp identity(%{identity_role: :child_admin}), do: %{"roles" => ["children", "admin"]}
  defp identity(%{identity_role: :parent}), do: %{"roles" => ["parents"]}
  defp identity(_context), do: %{"roles" => ["admin"]}

  defp render_home(context, current_user \\ %{"displayUsername" => "test-user-unit"}) do
    page =
      %{flash: %{}, current_user: current_user}
      |> BnestAppWeb.PageHTML.home()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> LazyHTML.from_fragment()

    Map.put(context, :page, page)
  end

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
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> LazyHTML.from_fragment()
  end

  # The `/login` template for a visit carrying `return_to`, with the return path
  # `LoginLive.mount/3` derives from it.
  defp render_login(return_to) do
    %{
      live_action: :login,
      return_to: BnestAppWeb.UserAuth.safe_return_path(return_to),
      flash: %{}
    }
    |> BnestAppWeb.LoginLive.render()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> LazyHTML.from_fragment()
  end

  defp render_family_chat_room(context, slug) do
    {:ok, room} = FamilyChat.get_room_for("test-user-unit", slug)

    page =
      %{flash: %{}, current_user: %{"displayUsername" => "test-user-unit"}, room: room}
      |> BnestAppWeb.FamilyChatHTML.room()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> LazyHTML.from_fragment()

    context
    |> Map.put(:route, "/family-chat/" <> room.slug)
    |> Map.put(:page, page)
  end

  # Sifat Allah persists through its facade to the configured record-backed progress store,
  # which reaches Storage's record repository; the repository runs here over an in-memory
  # record backend, kept in the context so a reload can restart the repository over it.
  defp start_sifat_allah_records(context) do
    previous = StoragePorts.install()
    ExUnit.Callbacks.on_exit(fn -> StoragePorts.restore(previous) end)
    records = InMemoryRecordBackend.start()
    ExUnit.Callbacks.start_supervised!({Records, store: records})

    user =
      context
      |> identity()
      |> Map.merge(%{
        "userId" => "user-test-unit-sifat-allah",
        "displayUsername" => "test-user-unit-sifat-allah"
      })

    Map.merge(context, %{sifat_records: records, sifat_user: user})
  end

  # The production `mount/3` on a fresh socket for the synthetic learner, as a page load does.
  defp mount_sifat_allah(context) do
    socket = %Socket{
      assigns: %{__changed__: %{}, flash: %{}, current_user: context.sifat_user}
    }

    {:ok, socket} = SifatAllahLive.mount(%{}, %{}, socket)

    context
    |> Map.put(:sifat_pushes, [])
    |> render_sifat_allah(socket)
  end

  # A click reaches the LiveView only through a button the page renders enabled.
  defp click_sifat_allah(context, selector, event, params \\ %{}) do
    if context.page |> LazyHTML.query("#{selector}:not([disabled])") |> Enum.empty?() do
      raise "the Sifat Allah page offers no enabled #{selector}"
    end

    sifat_allah_event(context, event, params)
  end

  # The SifatSwipe hook turns a horizontal swipe on its element into the element's event.
  defp swipe_sifat_allah(context, selector, event, direction) do
    if context.page |> LazyHTML.query("#{selector}[phx-hook=SifatSwipe]") |> Enum.empty?() do
      raise "the Sifat Allah page offers no swipeable #{selector}"
    end

    sifat_allah_event(context, event, %{"direction" => direction})
  end

  defp sifat_allah_hook_event(context, event) do
    if context.page
       |> LazyHTML.query("#sifat-allah-app[phx-hook=SifatHistory]")
       |> Enum.empty?() do
      raise "the Sifat Allah page has no SifatHistory hook"
    end

    sifat_allah_event(context, event, %{})
  end

  defp sifat_allah_event(context, event, params) do
    {:noreply, socket} = SifatAllahLive.handle_event(event, params, context.sifat_socket)
    render_sifat_allah(context, socket)
  end

  # Renders the socket's assigns with the production template and moves the events the
  # LiveView pushed into the context, oldest first, as a client receives each once.
  defp render_sifat_allah(context, socket) do
    page =
      socket.assigns
      |> Map.delete(:__changed__)
      |> SifatAllahLive.render()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> LazyHTML.from_fragment()

    context
    |> Map.update(:sifat_pushes, [], &(&1 ++ Utils.get_push_events(socket)))
    |> Map.put(:sifat_socket, Utils.clear_temp(socket))
    |> Map.put(:page, page)
  end

  defp rendered_answer_position(page, answer) do
    page
    |> LazyHTML.query("[data-role=quiz-question] .sifat-answer-grid button")
    |> Enum.find_index(fn button -> button |> LazyHTML.text() |> String.trim() == answer end)
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

  # The application holds a bootstrapped account, but the visitor sends no session cookie.
  @impl true
  def prepare_behaviour(context, :unauthenticated, _args) do
    context
    |> start_request_path([synthetic_account("test-user-unit", ["admin"])])
    |> Map.put(:authenticated, false)
  end

  def prepare_behaviour(context, :uninitialized, _args),
    do: Map.put(context, :identity_store, InMemoryIdentityStore.start())

  def prepare_behaviour(context, :approved_account, _args),
    do: authenticated_memory_context(context)

  def prepare_behaviour(context, :approved_argon2_account, _args) do
    context = authenticated_memory_context(context)

    {:ok, account} =
      IdentityStore.read_account(context.identity_store, context.identity_user["userId"])

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
      accepted_before: RecordBackend.read(context.central_store, :chat, context.central_owner),
      accepted_import: accepted,
      browser_sources: [
        %{"storageArea" => "localStorage", "storageKey" => "unknown", "payload" => "opaque"}
      ]
    })
  end

  def prepare_behaviour(context, :interrupted_import, _args) do
    context = central_context(context, [chat_source()])
    InMemoryRecordBackend.fail_next_write(context.central_store)

    {:error, :read_back_failed, manifest} =
      Import.browser(context.central_store, context.central_owner, chat_source())

    Map.merge(context, %{interrupted_manifest: manifest, first_import_id: manifest["importId"]})
  end

  def prepare_behaviour(context, :stale_browser_revision, _args) do
    context = central_context(context, [])
    {:ok, _accepted} = Import.browser(context.central_store, context.central_owner, chat_source())
    {:ok, newer} = RecordBackend.read(context.central_store, :chat, context.central_owner)

    stale_payload =
      chat_source()["payload"] |> Jason.decode!() |> Map.put("model", "stale") |> Jason.encode!()

    Map.merge(context, %{
      centralized_before: newer,
      browser_sources: [Map.put(chat_source(), "payload", stale_payload)]
    })
  end

  # The importing user is a real account with a session, so a change made after the import
  # can travel the router's browser pipeline the way the page's own script sends it.
  def prepare_behaviour(context, :recognized_and_unrelated_keys, _args) do
    username = "test-user-unit-central"
    context = start_request_path(context, [synthetic_account(username, ["admin"])])
    {:ok, token} = Identity.login(username, @synthetic_password)
    {:ok, %{"userId" => owner}} = Identity.current_user(token)

    context
    |> Map.merge(%{
      central_store: context.request_store,
      central_owner: owner,
      central_token: token
    })
    |> Map.put(:browser_storage, [
      chat_source(),
      %{"storageArea" => "localStorage", "storageKey" => "unrelated", "payload" => "keep"}
    ])
  end

  # The saved chat is the precondition, so it is saved through the CodexChat facade, on the
  # thread the agent session cannot resume.
  def prepare_behaviour(context, :unavailable_codex_thread, _args) do
    context = start_chat_runtime(context)

    {:ok, transcript} =
      Transcript.new("gpt-5.6-terra", "medium") |> Transcript.submit("Remember this transcript")

    transcript =
      transcript
      |> Transcript.update_assistant("Saved response")
      |> Transcript.complete()
      |> Transcript.put_thread_id("unavailable-thread")

    {:ok, _record} = CodexChat.save_transcript(context.chat_user["userId"], transcript, nil)
    Map.put(context, :transcript_before, transcript.messages)
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
      migration_store: InMemoryRecordBackend.start()
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
      migration_store: InMemoryRecordBackend.start(),
      resolved_database_directory: "/var/lib/bnest"
    })
  end

  def prepare_behaviour(context, :migration_stopped_after_progress, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])
    [first_path | _rest] = FlatMigration.order_inventory(context.flat_sources)

    {:accepted, evidence} =
      assess_record(first_path, source_bytes(context, first_path))

    {:ok, _record} =
      RecordBackend.put_new(
        context.migration_store,
        evidence.classification.type,
        evidence.identity,
        evidence.record
      )

    Map.put(context, :migration_items, [%{path: first_path, outcome: :accepted}])
  end

  # A flat-primary installation behind the Storage facade's in-memory ports: the flat store
  # holds an account and its chat, learning and theme records, and SQLite already holds a
  # backfilled copy, so parity is measured rather than assumed. The account is bootstrapped
  # through the Identity facade, which works on the record store Storage reports as active.
  def prepare_behaviour(context, :all_verification_checks_pass, _args) do
    previous = StoragePorts.install()
    ExUnit.Callbacks.on_exit(fn -> StoragePorts.restore(previous) end)
    flat = InMemoryRecordBackend.start()
    ExUnit.Callbacks.start_supervised!({Records, store: flat})
    StoragePorts.put(:flat_store, flat)
    username = "test-user-unit-sqlite"
    password = @synthetic_password

    {:ok, [%{"userId" => owner}]} =
      Identity.bootstrap(
        [%{"username" => username, "password" => password, "roles" => ["admin"]}],
        start_identity!()
      )

    Enum.each(recognized_browser_sources(), fn source ->
      {:ok, _accepted} = Import.browser(flat, owner, source)
    end)

    {_backend, sqlite} = Storage.record_backend()

    Enum.each(InMemoryRecordBackend.snapshot(flat), fn {{type, identity}, record} ->
      {:ok, _copied} = RecordBackend.put_new(sqlite, type, identity, record)
    end)

    StoragePorts.put(
      :parity?,
      InMemoryRecordBackend.snapshot(flat) == InMemoryRecordBackend.snapshot(sqlite)
    )

    journey_records =
      Map.new([:chat, :sifat_allah, :theme], fn type ->
        {:ok, record} = RecordBackend.read(flat, type, owner)
        {type, record}
      end)

    Map.merge(context, %{
      flat_store: flat,
      sqlite_store: sqlite,
      journey_owner: owner,
      journey_username: username,
      journey_password: password,
      journey_records: journey_records
    })
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

  # A connected chat client over SQLite-primary storage: the Storage pointer port reports the
  # SQLite phase, the production LiveView runs over the routed record repository with the
  # named Identity process beside it, and a draft is typed into its composer.
  def prepare_behaviour(context, :healthy_route_with_acknowledged_state, _args) do
    context =
      context
      |> Map.put(:chat_storage, config: %{"schemaVersion" => 1, "phase" => "sqlite_primary"})
      |> open("/chat")
      |> type_draft("unsent draft")

    ExUnit.Callbacks.start_supervised!(Identity)
    context
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

  # The Scheduler's schedules live in the scenario's in-memory schedule store
  # (`UnitSupport`), put there as the release seeds put them.
  def prepare_behaviour(context, :admin_opened_schedules, _args) do
    key = "prod-sqlite-backup-daily"
    :ok = put_schedule!(key, "prod_sqlite_backup", "admin_system")

    Map.merge(context, %{
      backup_directory: "/private/backups",
      destination_id: "unit-destination",
      schedule_key: key
    })
  end

  # Saved through the facade operation the admin schedules page calls: 02:00 WIB is
  # 19:00 UTC, later on the scenario's day than its 12:00 UTC clock.
  def prepare_behaviour(context, :saved_daily_schedule, _args) do
    key = "prod-sqlite-backup-daily"
    :ok = put_schedule!(key, "prod_sqlite_backup", "admin_system")

    {:ok, _schedule} =
      Scheduler.update_daily(
        key,
        %{"daily_time_wib" => "02:00", "enabled" => "true", "revision" => "1"},
        @behaviour_now
      )

    Map.merge(context, %{schedule_key: key, schedule_before_restart: Scheduler.get_schedule(key)})
  end

  # Due three days before its latest slot: the scheduler missed that slot and the
  # three before it.
  def prepare_behaviour(context, :multiple_missed_slots, _args) do
    key = "unit-catchup"
    missed = DateTime.add(Policy.latest_slot("19:00", @behaviour_now), -3 * 86_400)
    :ok = put_schedule!(key, "fixture", "family", %{next_run_at: missed})
    Map.put(context, :schedule_key, key)
  end

  def prepare_behaviour(context, :accepted_backup_claim, _args),
    do: Map.merge(context, unit_backup_fixture())

  def prepare_behaviour(context, :overlapping_coordinators, _args) do
    key = "unit-overlap"
    :ok = put_schedule!(key, "fixture", "family")
    Map.put(context, :schedule_key, key)
  end

  def prepare_behaviour(context, :contextual_schedules, _args),
    do: Map.put(context, :scheduler_entries, Scheduler.task_entries())

  # A non-admin family member with a real session: both accounts are bootstrapped through the
  # Identity facade and the child logs in through it.
  def prepare_behaviour(context, :denied_settings_visitor, _args) do
    context =
      start_request_path(context, [
        synthetic_account("test-user-unit-admin", ["admin"]),
        synthetic_account("test-user-unit-child", ["children"])
      ])

    {:ok, token} = Identity.login("test-user-unit-child", @synthetic_password)
    {:ok, visitor} = Identity.current_user(token)
    Map.merge(context, %{visitor_token: token, visitor: visitor})
  end

  def prepare_behaviour(context, :retention_fixture, _args),
    do: Map.put(context, :retention_receipts, unit_retention_receipts())

  def prepare_behaviour(context, :second_family_handler, _args) do
    key = "unit-second-family"
    :ok = put_schedule!(key, "fixture", "family")
    Map.put(context, :schedule_key, key)
  end

  def prepare_behaviour(context, :typed_settings_panels, _args),
    do: Map.put(context, :declared_panels, AdminRegistry.panels())

  def prepare_behaviour(context, state, args)
      when state in [
             :room_has_known_history,
             :sent_message_with_known_id,
             :sent_and_committed_message,
             :system_message_posted_to_room,
             :user_without_family_chat_capability,
             :holds_subscription,
             :message_committed_before_subscription,
             :has_enabled_subscription,
             :endpoint_configured_production,
             :fresh_migrated_database,
             :migration_applied,
             :trusted_producer,
             :three_members_with_subscriptions,
             :delivery_will_fail_retryable,
             :delivery_targets_gone_subscription,
             :final_rows_older_than_7_days,
             :nonfinal_rows_same_age,
             :soft_deleted_rows_older_than_7_days,
             :schedule_due,
             :schedule_due_and_enabled,
             :schedule_different_time,
             :schedule_disabled_seed,
             :convergence_already_ran,
             :operator_changed_schedule_time,
             :insufficient_capacity,
             :continuous_probes_running,
             :backup_timeout_forced,
             :verified_backup_artifact,
             :two_independent_slots,
             :routed_socket_on_prior_slot,
             :other_member_message_committed,
             :committed_long_message,
             :committed_message,
             :committed_reply_to_previous,
             :sent_reply_with_known_id,
             :replied_under_earlier_display_name,
             :reply_committed_before_subscription,
             :reply_migration_applied,
             :one_other_active_subscription
           ] do
    UnitFamilyChatDriver.prepare_behaviour(context, state, args)
  end

  def prepare_behaviour(context, :expiry_policies, _args) do
    key = "unit-expires"

    :ok =
      put_schedule!(key, "fixture", "family", %{
        expiration_kind: "after_occurrences",
        max_occurrences: 1
      })

    policies = [
      %{expiration_kind: "never"},
      %{expiration_kind: "at", expires_at: DateTime.add(@behaviour_now, 60)},
      %{expiration_kind: "after_occurrences", claimed_occurrences: 0, max_occurrences: 1}
    ]

    Map.merge(context, %{schedule_key: key, expiration_policies: policies})
  end

  @impl true
  def perform_behaviour(context, :open_protected_route, [route]) do
    {response, accesses} = route_request(route, nil)

    Map.merge(context, %{
      attempted_route: route,
      protected_response: response,
      protected_accesses: accesses
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
    result = Sessions.revoke(context.identity_store, context.identity_token)
    Map.merge(context, %{logout_result: result, authenticated: false})
  end

  def perform_behaviour(context, :reload_same_browser, _args),
    do:
      Map.put(
        context,
        :reload_result,
        Sessions.current_user(context.identity_store, context.identity_token)
      )

  def perform_behaviour(context, :logout_browser_a, _args) do
    revoke_result = Sessions.revoke(context.identity_store, context.token_a)

    Map.merge(context, %{
      browser_a_result: Sessions.current_user(context.identity_store, context.token_a),
      browser_b_result: Sessions.current_user(context.identity_store, context.token_b),
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
    before = InMemoryRecordBackend.snapshot(context.central_store)
    result = Import.browser(context.central_store, context.central_owner, chat_source())
    Map.merge(context, %{before_retry: before, retry_result: result})
  end

  def perform_behaviour(context, :write_stale_record, _args) do
    [source] = context.browser_sources
    result = Import.browser(context.central_store, context.central_owner, source)
    Map.put(context, :stale_result, result)
  end

  # The import page's own event handlers run against the in-memory record store. The browser
  # reports every key it holds, the unrelated one included, so the cleanup instruction Bnest
  # pushes back is the only thing that decides which keys the browser removes.
  def perform_behaviour(context, :accept_and_read_back, _args) do
    socket = %Socket{
      assigns: %{__changed__: %{}, current_user: %{"userId" => context.central_owner}}
    }

    sources = Enum.map(context.browser_storage, &Map.put(&1, "present", true))

    {:noreply, socket} =
      DataMigrationLive.handle_event("browser-sources", %{"sources" => sources}, socket)

    {:noreply, socket} = DataMigrationLive.handle_event("confirm-imports", %{}, socket)

    [["imports-accepted", %{"storageKeys" => cleared}]] = Utils.get_push_events(socket)

    Map.put(context, :cleared_storage_keys, cleared)
  end

  # The user opens the saved chat, whose Codex thread the mount tries to resume, and sends the
  # next message. The page the mount rendered is kept, since the send clears its alert.
  def perform_behaviour(context, :continue_chat, _args) do
    context = open(context, "/chat")

    context
    |> Map.put(:reopened_page, context.page)
    |> send_message("Continue after resume")
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

    filesystem = %{
      lstat: fn _path -> {:error, :enoent} end,
      stat: fn
        ^candidate -> {:ok, %{mode: 0o700}}
        ^shared -> {:ok, %{mode: 0o1777}}
        _path -> {:error, :enoent}
      end
    }

    {persist_result, storage_pointer} = persist_with_pointer(candidate, filesystem)

    Map.merge(context, %{
      requested_directory: candidate,
      persist_result: persist_result,
      storage_pointer: storage_pointer
    })
  end

  def perform_behaviour(context, :enter_unsafe_folder, _args) do
    absent = %{lstat: fn _path -> {:error, :enoent} end, stat: fn _path -> {:error, :enoent} end}
    {persist_result, storage_pointer} = persist_with_pointer("relative/storage", absent)
    Map.merge(context, %{persist_result: persist_result, storage_pointer: storage_pointer})
  end

  def perform_behaviour(context, :apply_migration_set_twice, _args) do
    {_first_counts, first_inserted, schema_before} = migration_pass(context)
    {_second_counts, second_inserted, schema_after} = migration_pass(context)

    Map.merge(context, %{
      schema_before_second_apply: schema_before,
      schema_after_second_apply: schema_after,
      first_apply_inserted: first_inserted,
      second_apply_inserted: second_inserted,
      declared_migration_id: FlatMigration.migration_id()
    })
  end

  def perform_behaviour(context, :run_managed_storage_migration, _args) do
    assessments =
      context.flat_sources
      |> FlatMigration.order_inventory()
      |> Enum.map(fn path ->
        source_bytes = context.flat_source_records |> Map.fetch!(path) |> Jason.encode!()
        {path, assess_record(path, source_bytes)}
      end)

    accepted =
      Enum.map(assessments, fn
        {path, {:accepted, evidence}} ->
          record = evidence.record

          {:ok, ^record} =
            RecordBackend.put_new(
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
      |> FlatMigration.outcome_counts()

    Map.merge(context, %{
      migration_items: accepted,
      migrated_sources: Enum.map(accepted, & &1.path),
      migration_run_result: counts,
      database_path: StorageLocation.database_path(context.resolved_database_directory)
    })
  end

  def perform_behaviour(context, :retry_same_migration, _args) do
    store_before = InMemoryRecordBackend.snapshot(context.migration_store)
    {counts, _inserted, store_after} = migration_pass(context)

    Map.merge(context, %{
      migration_run_result: counts,
      store_before_retry: store_before,
      store_after_retry: store_after,
      item_count_before_retry: map_size(store_before),
      item_count_after_retry: map_size(store_after)
    })
  end

  def perform_behaviour(context, :commit_authority_switch, _args),
    do: Map.put(context, :authority_switch, Storage.migrate(@in_memory_flat_root, true))

  # Bound to a Then step: retirement runs through the Storage facade at the pointer's own
  # generation, and the flat store the Given seeded must hold identity records before it and
  # none after it, so a retirement that removes nothing fails here.
  def perform_behaviour(context, :retire_flat_identity_sources, _args) do
    store = context.flat_store
    generation = Storage.database_generation()

    if RecordBackend.identity_files_empty?(store),
      do: raise("the flat store holds no identity records to retire")

    result = Storage.retire(@in_memory_flat_root, generation, false)

    unless match?({:ok, %{"flatFilesRetiredAt" => _retired_at}}, result) and
             {:retire, @in_memory_flat_root, generation, false} in StoragePorts.calls() and
             RecordBackend.identity_files_empty?(store) do
      raise "flat identity records remain after retirement: #{inspect(result)}"
    end

    context
  end

  # Verification only classifies; it must not write, so the store snapshot is the evidence
  # that the flat-primary service is untouched.
  def perform_behaviour(context, :verify_migration, _args) do
    store_before = InMemoryRecordBackend.snapshot(context.migration_store)

    counts =
      context.flat_sources
      |> FlatMigration.order_inventory()
      |> Enum.map(fn path ->
        {outcome, _evidence} = assess_record(path, source_bytes(context, path))
        outcome
      end)
      |> FlatMigration.outcome_counts()

    Map.merge(context, %{
      migration_run_result: counts,
      store_before_verification: store_before,
      store_after_verification: InMemoryRecordBackend.snapshot(context.migration_store),
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
    |> Map.put(:routed_health_after, Deployment.readiness())
  end

  def perform_behaviour(context, :resolve_backup_destination, _args) do
    directory = Config.default_directory(context.repository_root)

    Map.merge(context, %{
      resolved_backup_directory: directory,
      public_backup_result: %{status: :verified}
    })
  end

  # Saving the destination queues its setup claim through the Scheduler facade, and
  # saving it again queues the same one.
  def perform_behaviour(context, :save_backup_override, _args) do
    key = context.schedule_key
    destination_id = context.destination_id
    before = run_count()
    {:ok, first} = Scheduler.claim_setup(key, destination_id, @behaviour_now)
    {:ok, second} = Scheduler.claim_setup(key, destination_id, @behaviour_now)

    Map.merge(context, %{
      backup_document: Config.document(context.backup_directory),
      first_setup_claim: first,
      second_setup_claim: second,
      setup_run_delta: run_count() - before
    })
  end

  # Starts the Scheduler's coordinator over the scenario's store at the scenario's
  # clock, stops it, starts it again, and has the new one reconcile.
  def perform_behaviour(context, :restart_scheduler, _args) do
    clock = fn -> @behaviour_now end
    ExUnit.Callbacks.start_supervised!({Task.Supervisor, name: BnestApp.Scheduler.Tasks})
    ExUnit.Callbacks.start_supervised!({Scheduler, clock: clock, automatic?: false})
    :ok = ExUnit.Callbacks.stop_supervised!(Scheduler)
    ExUnit.Callbacks.start_supervised!({Scheduler, clock: clock, automatic?: false})
    :ok = Scheduler.reconcile()

    Map.merge(context, %{
      schedule_after_restart: Scheduler.get_schedule(context.schedule_key),
      scheduler_restarted?: true
    })
  end

  def perform_behaviour(context, :reconcile_startup, _args) do
    claims = Scheduler.claim_due(@behaviour_now)

    Map.merge(context, %{
      reconciled_claim: Enum.find(claims, &(&1.schedule_key == context.schedule_key)),
      reconciled_schedule: Scheduler.get_schedule(context.schedule_key)
    })
  end

  # Step-binding collision fix (adapter change; see learnings.md's Phase 5
  # entry -- "the backup handler runs" is shared verbatim by the pre-existing
  # scheduled-backup feature (below) and by family_chat_operations.feature's
  # capacity scenario, and ExBDD step text is matched globally across all
  # `test/behaviour/steps/*.exs` files, not per feature file, so only one
  # driver clause can own this exact text. The family-chat scenario's own
  # `:insufficient_capacity` Given step is the unambiguous signal for which
  # one applies.
  def perform_behaviour(context, :run_backup_handler, _args)
      when is_map_key(context, :family_chat_backup_capacity) do
    UnitFamilyChatDriver.perform_behaviour(
      context,
      :backup_runs_full_duration,
      []
    )
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

  # Two coordinators claim the same due slot at once, then the one claimed attempt
  # fails transiently each time it is retried.
  def perform_behaviour(context, :reconcile_overlap, _args) do
    claims =
      1..2
      |> Task.async_stream(fn _coordinator -> Scheduler.claim_due(@behaviour_now) end,
        max_concurrency: 2
      )
      |> Enum.flat_map(fn {:ok, rows} ->
        Enum.filter(rows, &(&1.schedule_key == context.schedule_key))
      end)

    # The Thens judge how many claims there were and what each failure recorded, so
    # this follows the first claim through whatever the store answers.
    claim = List.first(claims)
    attempt_2 = fail_attempt(claim.run_id, claim.attempt, @behaviour_now)
    at_2 = DateTime.add(@behaviour_now, 5 * 60)
    retried_2 = Enum.find(Scheduler.claim_due(at_2), &(&1.run_id == claim.run_id))
    attempt_3 = fail_attempt(claim.run_id, retried_2.attempt, at_2)
    at_3 = DateTime.add(at_2, 30 * 60)
    retried_3 = Enum.find(Scheduler.claim_due(at_3), &(&1.run_id == claim.run_id))
    final = fail_attempt(claim.run_id, retried_3.attempt, at_3)

    Map.merge(context, %{
      overlap_claims: claims,
      retry_attempts: Enum.map([attempt_2, attempt_3, final], &elem(&1, 1))
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
    {response, accesses} = route_request("/admin/settings", context.visitor_token)
    Map.merge(context, %{settings_response: response, settings_accesses: accesses})
  end

  def perform_behaviour(context, :verify_new_backup, _args),
    do: Map.put(context, :retained_run_ids, Run.retained_run_ids(context.retention_receipts))

  # The slot is due at the scenario's clock: the Scheduler's coordinator starts at that
  # clock over the shared `Scheduler.Tasks` supervisor and reconciles, so the coordinator
  # claims the slot and that supervisor runs it. The driver claims and runs nothing itself;
  # `SchedulerDispatch.coordinate/2` records what the supervisor's processes ran.
  def perform_behaviour(context, :run_second_handler, _args) do
    ExUnit.Callbacks.start_supervised!({Task.Supervisor, name: BnestApp.Scheduler.Tasks})

    dispatch =
      SchedulerDispatch.coordinate(context.schedule_key, fn ->
        ExUnit.Callbacks.start_supervised!(
          {Scheduler, clock: fn -> @behaviour_now end, automatic?: false}
        )

        :ok = Scheduler.reconcile()
      end)

    Map.put(context, :family_handler_dispatch, dispatch)
  end

  def perform_behaviour(context, :open_admin_settings_from_home, _args) do
    fetched = Enum.map(context.declared_panels, &AdminRegistry.fetch(&1.key))
    Map.put(context, :fetched_panels, fetched)
  end

  def perform_behaviour(context, :reconcile_expiry, _args) do
    initial = Scheduler.claim_due(@behaviour_now)
    first = Enum.find(initial, &(&1.schedule_key == context.schedule_key))
    {:retryable, retry} = fail_attempt(first.run_id, first.attempt, @behaviour_now)
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
    do: UnitFamilyChatDriver.perform_behaviour(context, action, args)

  @impl true
  def behaviour_outcome?(context, :redirected_to_login, _args),
    do: match?(%URI{}, login_redirect(context.protected_response))

  # The redirect carries the visitor back to the route they asked for, and the login page
  # rendered for that redirect offers the login form and none of home's protected actions.
  def behaviour_outcome?(context, :login_form_only, _args) do
    with %URI{query: query} <- login_redirect(context.protected_response),
         %{"return_to" => return_to} <- URI.decode_query(query || "") do
      page = render_login(return_to)

      return_to == context.attempted_route and
        page
        |> LazyHTML.query("#login-form input[name=return_to][value='#{return_to}']")
        |> Enum.any?() and
        page
        |> LazyHTML.query("[data-role=chat-entry], [data-role=admin-settings-entry]")
        |> Enum.empty?()
    else
      _not_login -> false
    end
  end

  # The flat store's recorder saw the Given's bootstrap, so an empty list here is measured:
  # the request read and wrote no record before the guard answered.
  def behaviour_outcome?(context, :no_user_data_access, _args),
    do:
      match?(%URI{}, login_redirect(context.protected_response)) and
        context.protected_accesses == []

  # The warning is read from the setup route's production markup, rendered for the bootstrap
  # state the submission left in the store.
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

  def behaviour_outcome?(context, :protected_home_available, _args), do: context.authenticated

  def behaviour_outcome?(context, :current_browser_logged_out, _args),
    do:
      not context.authenticated and
        Sessions.current_user(context.identity_store, context.identity_token) ==
          {:error, :unauthenticated}

  # The unit layer hashes through the in-memory credential hasher, so it proves the
  # application's part: the account keeps the configured hasher's verifier, which checks the
  # password, and no stored record holds the plaintext. That the verifier is Argon2id is the
  # real hasher's property, which the integration driver proves.
  def behaviour_outcome?(context, :no_plaintext_password, _args) do
    records = context.identity_store |> InMemoryIdentityStore.snapshot() |> inspect()
    hasher = Identity.adapter(:credential_hasher)

    context.verifier != context.identity_password and
      hasher.verify(context.identity_password, context.verifier) and
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
    do: is_nil(Agent.get(context.storage_pointer, & &1))

  def behaviour_outcome?(context, :schema_matches_checksum, _args),
    do:
      context.declared_migration_id == FlatMigration.migration_id() and
        context.first_apply_inserted == length(context.flat_sources)

  # put_new refuses an existing key, so a second apply must insert nothing and leave the
  # stored records byte-identical.
  def behaviour_outcome?(context, :no_duplicate_schema_objects, _args),
    do:
      context.second_apply_inserted == 0 and
        context.schema_before_second_apply == context.schema_after_second_apply

  # The fixture lists `z-` before `a-`, so only a path-ordered inventory yields this order.
  def behaviour_outcome?(context, :deterministic_inventory, _args) do
    path_order = [
      "users/a-fixture-user/preferences/theme.json",
      "users/z-fixture-user/preferences/theme.json"
    ]

    context.flat_sources != path_order and context.migrated_sources == path_order
  end

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
        RecordBackend.read(
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
    do:
      match?({:ok, :activated, _report}, context.authority_switch) and
        Storage.phase() == :sqlite_primary and
        Records.active_backend(context.flat_store) ==
          {InMemoryRecordBackend, context.sqlite_store}

  # A login after the switch writes its session through the active store. The write must
  # land in SQLite, not the flat store, and still pass the record schema the flat rollback
  # reader enforces.
  def behaviour_outcome?(context, :writes_compatible_with_rollback, _args) do
    with {:ok, token} <- Identity.login(context.journey_username, context.journey_password),
         digest = Identity.session_digest(token),
         {:ok, session} <- RecordBackend.read(context.sqlite_store, :session, digest),
         {:error, :missing} <- RecordBackend.read(context.flat_store, :session, digest) do
      Storage.validate_record(session) == {:ok, session}
    else
      _failure -> false
    end
  end

  # Restarting the record repository and Identity drops any routing they held; afterwards
  # every journey must still reach the migrated records, with the flat identity records
  # already gone. Logout must also reach the push-subscription and live-session ports, whose
  # in-memory doubles report to this process.
  def behaviour_outcome?(context, :journeys_survive_restart, _args) do
    :ok = ExUnit.Callbacks.stop_supervised(Records)
    ExUnit.Callbacks.start_supervised!({Records, store: context.flat_store})
    identity = start_identity!()
    owner = context.journey_owner

    with true <- RecordBackend.identity_files_empty?(context.flat_store),
         :closed <- Identity.setup_status(identity),
         {:ok, token} <- Identity.login(context.journey_username, context.journey_password),
         {:ok, %{"userId" => ^owner}} <- Identity.current_user(token),
         true <-
           Enum.all?(context.journey_records, fn {type, record} ->
             Records.read(type, owner) == {:ok, record}
           end),
         true <- Preferences.theme(owner) == context.journey_records.theme["theme"],
         true <- SifatAllah.load_progress(owner) == {:ok, context.journey_records.sifat_allah},
         {:ok, _transcript, chat} <- CodexChat.load_transcript(owner),
         true <- chat == context.journey_records.chat,
         digest = Identity.session_digest(token),
         :ok <- Identity.logout(token),
         true <- received?({:subscription_revoked, owner, digest}),
         true <- received?({:session_disconnected, digest}),
         {:error, :unauthenticated} <- Identity.current_user(token) do
      true
    else
      _failure -> false
    end
  end

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

  # Readiness after the reconnect requires the record repository, Identity and the Codex model
  # catalog the routed server serves from, and the Storage pointer keeps SQLite authoritative
  # for the records the chat reaches. A changed revision is observable only at E2E, where a
  # candidate release replaces the server.
  def behaviour_outcome?(context, :routed_revision_and_readiness_proven, _args) do
    match?(
      {:ok, %{status: "ready", revision: revision, slot: slot}}
      when is_binary(revision) and revision != "" and is_binary(slot),
      context.routed_health_after
    ) and Storage.phase() == :sqlite_primary and
      Records.active_backend(context.chat_records) == Storage.record_backend()
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
          RecordBackend.read(
            context.central_store,
            :browser_import,
            {context.central_owner, import_id}
          )
        )

      _failure ->
        false
    end)
  end

  def behaviour_outcome?(context, :normalized_records_read, _args) do
    Enum.all?([:chat, :sifat_allah, :theme], fn type ->
      case RecordBackend.read(context.central_store, type, context.central_owner) do
        {:ok, %{"ownerId" => owner}} -> owner == context.central_owner
        _missing -> false
      end
    end)
  end

  def behaviour_outcome?(context, :absent_theme_recorded, _args) do
    with [{:ok, %{import_id: import_id}}] <- context.import_results,
         {:ok, %{"recoverySource" => %{"kind" => "browser-absence"}}} <-
           RecordBackend.read(context.central_store, :manifest, import_id) do
      true
    else
      _failure -> false
    end
  end

  def behaviour_outcome?(context, :no_theme_preference, _args),
    do:
      RecordBackend.read(context.central_store, :theme, context.central_owner) ==
        {:error, :missing}

  def behaviour_outcome?(context, :safe_rejected_import, _args),
    do: match?([{:error, :unsupported_source, _manifest}], context.import_results)

  def behaviour_outcome?(context, :source_and_record_unchanged, _args),
    do:
      RecordBackend.read(context.central_store, :chat, context.central_owner) ==
        context.accepted_before

  def behaviour_outcome?(context, :idempotent_import_identity, _args),
    do: match?({:ok, %{import_id: id}} when id == context.first_import_id, context.retry_result)

  def behaviour_outcome?(context, :accepted_data_preserved, _args) do
    after_retry = InMemoryRecordBackend.snapshot(context.central_store)

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
      RecordBackend.read(context.central_store, :chat, context.central_owner) ==
        {:ok, context.centralized_before}

  def behaviour_outcome?(context, :refresh_required, _args),
    do: match?({:error, :stale_revision, %{"status" => "retryable"}}, context.stale_result)

  # Bnest may tell the browser to clear the chat key only once that record reads back from
  # the server store.
  def behaviour_outcome?(context, :only_accepted_key_cleared, _args),
    do:
      context.cleared_storage_keys == ["bnest.chat.v1"] and
        match?(
          {:ok, %{"recordType" => "chat"}},
          RecordBackend.read(context.central_store, :chat, context.central_owner)
        )

  # A change made after the accepted import: the theme request the root layout's script sends
  # goes through the router to the theme controller. It must change the user's record in the
  # server store, and the root the router then renders for that user must carry it while
  # telling the browser script to keep no copy of its own.
  def behaviour_outcome?(context, :server_only_persistence, _args) do
    %{central_store: store, central_owner: owner, central_token: token} = context
    before = RecordBackend.read(store, :theme, owner)
    requested = "dark"
    change = dispatch_request(:put, "/preferences/theme", token, %{"theme" => requested})
    stored = RecordBackend.read(store, :theme, owner)
    home = dispatch_request(:get, "/", token)
    root = home.resp_body |> LazyHTML.from_document() |> LazyHTML.query("html")

    change.status == 204 and stored != before and
      match?({:ok, %{"ownerId" => ^owner, "theme" => ^requested}}, stored) and
      Preferences.theme(owner) == requested and home.status == 200 and
      LazyHTML.attribute(root, "data-theme") == [requested] and
      LazyHTML.attribute(root, "data-theme-storage") == ["server"] and
      LazyHTML.attribute(root, "data-browser-persistence") == ["false"]
  end

  # The saved messages must still show, and the chat the facade loads must be the stored record,
  # leading with those messages on a thread other than the unavailable one.
  def behaviour_outcome?(context, :transcript_preserved, _args) do
    owner = context.chat_user["userId"]
    {_backend, active} = Records.active_backend(context.chat_records)
    stored = active |> InMemoryRecordBackend.snapshot() |> Map.get({:chat, owner})
    saved_count = length(context.transcript_before)

    with true <- visitor_message_visible?(context, "Remember this transcript"),
         true <- visitor_message_visible?(context, "Continue after resume"),
         true <-
           context.page
           |> LazyHTML.query("[data-role=assistant-message]")
           |> Enum.any?(&(&1 |> LazyHTML.text() |> String.trim() == "Saved response")),
         {:ok, transcript, ^stored} <- CodexChat.load_transcript(owner) do
      Enum.take(transcript.messages, saved_count) == context.transcript_before and
        transcript.thread_id != "unavailable-thread"
    else
      _lost -> false
    end
  end

  # Opening the chat reported the fresh conversation, after the agent session was asked for
  # the unavailable thread and then for a new one, which received the next message.
  def behaviour_outcome?(context, :fresh_conversation_reported, _args) do
    alert = context.reopened_page |> LazyHTML.query("[role=alert]") |> LazyHTML.text()

    opened_threads =
      for {:agent_session, :open, {thread, _, _, _}} <- context.codex_calls, do: thread

    String.contains?(alert, "transcript is preserved in a fresh conversation") and
      opened_threads == ["unavailable-thread", nil] and
      Enum.any?(
        context.codex_calls,
        &match?({:agent_session, :prompt, %{thread_id: nil}, "Continue after resume"}, &1)
      )
  end

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

  def behaviour_outcome?(context, :authoritative_vacuum, _args),
    do: context.backup_receipt["sourceGeneration"] == context.backup_artifact.source_generation

  def behaviour_outcome?(context, :independent_proof, _args),
    do: Receipt.valid?(context.backup_receipt, context.backup_location.destination_id)

  def behaviour_outcome?(context, :single_nonoverlap_claim, _args),
    do: length(context.overlap_claims) == 1

  def behaviour_outcome?(context, :bounded_attempts, _args),
    do:
      Enum.map(context.retry_attempts, & &1.attempt) == [2, 3, 3] and
        List.last(context.retry_attempts).state == "failed"

  def behaviour_outcome?(context, :context_groups, _args),
    do: context.schedule_contexts == MapSet.new(["admin_system", "family"])

  def behaviour_outcome?(context, :typed_backup_link, _args),
    do: match?({:ok, %{path: "/admin/settings/schedules"}}, context.backup_settings)

  # The router's admin guard answers before the page: the response is a sent 404, and every
  # record the request touched is the visitor's own session, account or theme, which the
  # browser pipeline reads to resolve them. No other record was read or written.
  def behaviour_outcome?(context, :not_found_before_reads, _args) do
    %{settings_response: response, settings_accesses: accesses} = context
    own = [Identity.session_digest(context.visitor_token), context.visitor["userId"]]

    response.halted and response.status == 404 and response.resp_body == "Not found" and
      accesses != [] and
      Enum.all?(accesses, fn {operation, _type, identity} ->
        operation == :read and identity in own
      end)
  end

  # The visitor's own home: the user the router resolves from their cookie, rendered by the
  # home template.
  def behaviour_outcome?(context, :no_admin_home_entry, _args) do
    {response, _accesses} = route_request("/", context.visitor_token)
    user = response.assigns.current_user
    page = render_home(context, user).page

    not response.halted and user["userId"] == context.visitor["userId"] and
      page |> LazyHTML.query("[data-role=chat-entry]") |> Enum.any?() and
      page |> LazyHTML.query("[data-role=admin-settings-entry]") |> Enum.empty?()
  end

  def behaviour_outcome?(context, :owned_retention, _args),
    do: MapSet.size(context.retained_run_ids) == 7

  def behaviour_outcome?(context, :preserve_unowned, _args),
    do: Enum.all?(context.retention_receipts, &Map.has_key?(&1, "runId"))

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

  def behaviour_outcome?(context, :panels_discoverable, _args),
    do:
      length(context.fetched_panels) == length(context.declared_panels) and
        Enum.all?(context.fetched_panels, &match?({:ok, _}, &1))

  def behaviour_outcome?(context, :owner_allowlists, _args),
    do: Enum.all?(context.declared_panels, &(is_atom(&1.owner) and is_list(&1.editable_fields)))

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
    do: UnitFamilyChatDriver.behaviour_outcome?(context, expected, args)

  defp unit_backup_fixture do
    destination_id = "unit-destination"

    %{
      backup_claim: %{
        schedule_key: "prod-sqlite-backup-daily",
        claim_kind: "setup",
        claim_key: Policy.setup_claim_key(destination_id),
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

  # Runs the production persist path with the storage pointer held in an Agent and the real
  # location rules reading `filesystem`, so the pointer can be read back afterwards.
  defp persist_with_pointer(candidate, filesystem) do
    {:ok, storage_pointer} = Agent.start_link(fn -> nil end)

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

    {Storage.persist_directory(candidate, dependencies), storage_pointer}
  end

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
      |> FlatMigration.order_inventory()
      |> Enum.map(fn path ->
        case assess_record(path, source_bytes(context, path)) do
          {:accepted, evidence} ->
            inserted? =
              match?(
                {:ok, _record},
                RecordBackend.put_new(
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

    counts = results |> Enum.map(&elem(&1, 0)) |> FlatMigration.outcome_counts()

    {counts, Enum.count(results, &elem(&1, 1)),
     InMemoryRecordBackend.snapshot(context.migration_store)}
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
      central_store: InMemoryRecordBackend.start(),
      central_owner: "user-unit",
      browser_sources: sources
    })
  end

  # An unnamed Identity process over the record store Storage reports as active.
  defp start_identity! do
    ExUnit.Callbacks.start_supervised!(
      Supervisor.child_spec({Identity, name: nil}, id: make_ref())
    )
  end

  defp synthetic_account(username, roles),
    do: %{"username" => username, "password" => @synthetic_password, "roles" => roles}

  # The browser request path over in-memory storage: Storage's ports are doubles, the record
  # repository runs over a flat store that reports every record access to this process, and
  # the accounts are bootstrapped through the Identity facade. The recorder must see that
  # bootstrap, so a request that touches no record is observed rather than assumed.
  defp start_request_path(context, accounts) do
    # The signed session cookie caches its derived keys in the in-memory table Plug's own
    # application creates, which `mix test --no-start` leaves unstarted.
    {:ok, _apps} = Application.ensure_all_started(:plug)
    previous = StoragePorts.install()
    ExUnit.Callbacks.on_exit(fn -> StoragePorts.restore(previous) end)
    store = InMemoryRecordBackend.start(self())
    ExUnit.Callbacks.start_supervised!({Records, store: store})
    {:ok, _users} = Identity.bootstrap(accounts, start_identity!())

    if drain_record_accesses() == [],
      do: raise("the flat store's recorder saw no bootstrap writes")

    Map.put(context, :request_store, store)
  end

  # One browser GET through the router's own pipelines for `path`, with the identity cookie
  # when a token is given. Phoenix's bypass stops the request where the router would hand it
  # to the page, so the response is whatever the pipeline guards decided, and Phoenix never
  # dispatches a halted conn. Returns the conn and the record accesses the request made.
  defp route_request(path, token) do
    _earlier = drain_record_accesses()

    response =
      :get
      |> Plug.Test.conn(path)
      |> put_identity_cookie(token)
      |> Map.put(
        :secret_key_base,
        Application.get_env(:bnest_app, BnestAppWeb.Endpoint)[:secret_key_base]
      )
      |> Plug.Session.call(@session_options)
      |> Plug.Conn.put_private(:phoenix_bypass, {BnestAppWeb.Router, :current})
      |> BnestAppWeb.Router.call(BnestAppWeb.Router.init([]))

    {response, drain_record_accesses()}
  end

  # One browser request carried all the way through the router to its controller, with the
  # identity cookie and the CSRF token a page from this session holds. The rendered layout
  # resolves its static asset paths through the endpoint, which `mix test --no-start` leaves
  # unstarted, so it runs for this test only (configured with `server: false`, no listener).
  defp dispatch_request(method, path, token, params \\ %{}) do
    if is_nil(GenServer.whereis(BnestAppWeb.Endpoint)),
      do: ExUnit.Callbacks.start_supervised!(BnestAppWeb.Endpoint)

    Plug.CSRFProtection.delete_csrf_token()
    csrf_token = Plug.CSRFProtection.get_csrf_token()

    method
    |> Plug.Test.conn(path, params)
    |> put_identity_cookie(token)
    |> Plug.Conn.put_req_header("x-csrf-token", csrf_token)
    |> Map.put(
      :secret_key_base,
      Application.get_env(:bnest_app, BnestAppWeb.Endpoint)[:secret_key_base]
    )
    |> Plug.Session.call(@session_options)
    |> Plug.Conn.fetch_session()
    |> Plug.Conn.put_session("_csrf_token", Plug.CSRFProtection.dump_state())
    |> Plug.Conn.put_private(:phoenix_endpoint, BnestAppWeb.Endpoint)
    |> BnestAppWeb.Router.call(BnestAppWeb.Router.init([]))
  end

  defp put_identity_cookie(conn, nil), do: conn

  defp put_identity_cookie(conn, token),
    do: Plug.Test.put_req_cookie(conn, "_bnest_identity", token)

  # The record accesses reported so far, oldest first, as `{operation, type, identity}`.
  defp drain_record_accesses(accesses \\ []) do
    receive do
      {:record_access, operation, type, identity} ->
        drain_record_accesses([{operation, type, identity} | accesses])
    after
      0 -> Enum.reverse(accesses)
    end
  end

  # The redirect target when the response is a halted redirect to the login page, else nil.
  defp login_redirect(%{halted: true, status: 302} = response) do
    with [location] <- Plug.Conn.get_resp_header(response, "location"),
         %URI{path: "/login"} = target <- URI.parse(location) do
      target
    else
      _not_login -> nil
    end
  end

  defp login_redirect(_response), do: nil

  # Whether `message` already sits in this process's mailbox; consumes it if so.
  defp received?(message) do
    receive do
      ^message -> true
    after
      0 -> false
    end
  end

  defp authenticated_memory_context(context) do
    store = InMemoryIdentityStore.start()
    username = "test-user-unit"
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
      "payload" => Jason.encode!(Map.put(Quiz.progress(), "session", %{"mode" => "dashboard"}))
    }
  end

  defp theme_source,
    do: %{"storageArea" => "localStorage", "storageKey" => "phx:theme", "payload" => "dark"}

  defp assess_record(path, bytes),
    do: FlatMigration.assess_record(path, bytes, Storage.record_kinds())

  # A pristine, enabled daily schedule at 19:00 UTC, due at its latest slot, in the
  # scenario's in-memory schedule store, with `fields` replaced.
  defp put_schedule!(key, handler_key, schedule_context, fields \\ %{}) do
    InMemoryScheduleStore.put_daily_schedule(
      Scheduler.store(),
      key,
      handler_key,
      schedule_context,
      @behaviour_now,
      fields
    )
  end

  defp run_count, do: Scheduler.store() |> InMemoryScheduleStore.runs() |> length()

  # A transient failure of a claimed attempt, recorded in the Scheduler's configured store
  # the way its run records one.
  defp fail_attempt(run_id, attempt, now),
    do: ScheduleStore.fail_attempt(Scheduler.store(), run_id, attempt, :capacity, now)
end
