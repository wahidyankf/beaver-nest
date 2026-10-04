defmodule BnestApp.Behaviour.UnitHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver

  import BnestApp.Test.BehaviourEvidence

  alias BnestApp.Backup
  alias BnestApp.Backup.Domain.Receipt
  alias BnestApp.Behaviour.UnitFamilyChatDriver
  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.CodexChat.ModelCatalog
  alias BnestApp.FamilyChat
  alias BnestApp.Identity
  alias BnestApp.Identity.{Bootstrap, Login, Sessions}
  alias BnestApp.Identity.Domain.Authorization
  alias BnestApp.Operations
  alias BnestApp.Preferences
  alias BnestApp.Scheduler
  alias BnestApp.Scheduler.Domain.Policy
  alias BnestApp.Scheduler.Ports.ScheduleStore
  alias BnestApp.SifatAllah
  alias BnestApp.SifatAllah.Domain.Quiz
  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.CanonicalJson
  alias BnestApp.Storage.Domain.FlatMigration
  alias BnestApp.Storage.Domain.Location, as: StorageLocation
  alias BnestApp.Storage.Import
  alias BnestApp.Storage.Migration, as: StorageMigration
  alias BnestApp.Storage.Ports.RecordBackend
  alias BnestApp.Storage.Records
  alias BnestApp.Test.BackupIntegrity
  alias BnestApp.Test.CodexFixtureConversation
  alias BnestApp.Test.CodexFixtureModels, as: FixtureModels
  alias BnestApp.Test.InMemory.AgentSession, as: InMemoryAgentSession
  alias BnestApp.Test.InMemory.ArtifactStore, as: InMemoryArtifactStore
  alias BnestApp.Test.InMemory.BackupConfigStore, as: InMemoryBackupConfigStore
  alias BnestApp.Test.InMemory.DatabaseSnapshot, as: InMemoryDatabaseSnapshot
  alias BnestApp.Test.InMemory.IdentityStore, as: InMemoryIdentityStore
  alias BnestApp.Test.InMemory.IgnoreCheck, as: InMemoryIgnoreCheck
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.ReleaseEnvironment, as: InMemoryReleaseEnvironment
  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestApp.Test.InMemory.StoragePorts.{FlatSource, MigrationLedger}
  alias BnestApp.Test.IntegrityLabel
  alias BnestApp.Test.ObservedArtifactStore
  alias BnestApp.Test.RestoreDrill
  alias BnestApp.Test.SchedulerDispatch
  alias BnestAppWeb.AdminScheduleSettingsLive
  alias BnestAppWeb.ChatLive
  alias BnestAppWeb.DataMigrationLive
  alias BnestAppWeb.SifatAllahLive
  alias BnestAppWeb.StorageLive
  alias Mix.Tasks.Bnest.Backup.Reconcile
  alias Phoenix.HTML.Safe
  alias Phoenix.LiveView.{Socket, Utils}

  @behaviour_now ~U[2026-09-04 12:00:00Z]
  @composer_textarea "form#chat-composer-form textarea[data-role=chat-composer]"
  @composer_button "form#chat-composer-form .send-button"
  @in_memory_flat_root "/in-memory/flat"
  @acknowledged_message "Acknowledged before rollout"
  @synthetic_password "Synthetic password 1!"
  @unit_admin %{
    "userId" => "test-user-unit-admin",
    "displayUsername" => "test-user-unit-admin",
    "roles" => ["admin"]
  }

  # The backup-integrity states, actions and checks `BnestApp.Test.BackupIntegrity` serves in
  # both layers; the Givens that start from a destination establish it here first.
  @integrity_destination_prepares BackupIntegrity.destination_prepares()
  @integrity_prepares BackupIntegrity.prepares()
  @integrity_performs BackupIntegrity.performs()
  @integrity_outcomes BackupIntegrity.outcomes()
  @label_outcomes IntegrityLabel.outcomes()

  # The same for the restore drill (`BnestApp.Test.RestoreDrill`).
  @drill_destination_prepares RestoreDrill.destination_prepares()
  @drill_prepares RestoreDrill.prepares()
  @drill_performs RestoreDrill.performs()
  @drill_outcomes RestoreDrill.outcomes()

  # The statuses the schedules page may show for a schedule without exposing its failure.
  @safe_schedule_status ~r/Enabled|Running|Verified|Never run/u

  # A storage location already chosen, so the Storage panel's owner has saved state.
  @configured_storage_pointer %{
    "schemaVersion" => 1,
    "databaseDirectory" => "/srv/test-user-storage/data",
    "databaseFilename" => "bnest.sqlite3",
    "phase" => "flat_primary",
    "migrationId" => "flat-files-v1-to-sqlite-v1"
  }

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

  def open(%{authenticated: true} = context, "/"), do: render_home(context)

  # A visitor with no session is routed from "/" like a browser: the document it lands on.
  def open(context, "/"), do: Map.put(context, :page, visitor_document(context, "/"))

  def open(context, "/apps/sifat-allah") do
    context |> start_sifat_allah_records() |> mount_sifat_allah()
  end

  # The browser lands wherever the router's "/family-chat" action redirects it to.
  # A location naming no room the visitor may open is the controller's "Not found" page.
  def open(context, "/family-chat") do
    location = family_chat_redirect_location()
    slug = String.replace_prefix(location, "/family-chat/", "")

    case FamilyChat.get_room_for("test-user-unit", slug) do
      {:ok, _room} ->
        context |> render_family_chat_room(slug) |> Map.put(:route, location)

      {:error, _safe_error} ->
        context
        |> Map.put(:route, location)
        |> Map.put(:page, LazyHTML.from_fragment("Not found"))
    end
  end

  def open(context, "/family-chat/" <> slug) do
    render_family_chat_room(context, slug)
  end

  @impl true
  def brand_logo_visible?(context) do
    context.page
    |> LazyHTML.query("img[src='/images/beaver-nest-logo.png'][alt='Beaver Nest logo']")
    |> Enum.any?()
  end

  # Installability is what the document a visitor landed on after opening "/" declares: the
  # root layout's manifest and icon links, each at a path the endpoint serves statically.
  # The manifest's contents and service-worker activation are proven at E2E.
  @impl true
  def installable_as_app?(context) do
    document = context.page
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
    not Enum.empty?(LazyHTML.query(context.page, "main.home-shell")) and
      context.page |> LazyHTML.query("[data-role=data-migration-entry]") |> Enum.empty?()
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
    enabled?(context.page, @composer_textarea) and enabled?(context.page, @composer_button)
  end

  @impl true
  def composer_unavailable?(context) do
    disabled?(context.page, @composer_textarea) and disabled?(context.page, @composer_button)
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
    context = stream_answer(context)
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
        do: stream_answer(remounted),
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
    enabled_button?(context.page, "button[phx-click=start-learning]", "Belajar 3 Pasangan")
  end

  @impl true
  def quiz_mode_available?(context),
    do: enabled_button?(context.page, "button[phx-click=start-quiz]", "Latihan Ujian")

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

  # The card's colours come from the stylesheet's `.sifat-wajib-side` (green) and
  # `.sifat-mustahil-side` (orange) rules, so each side must carry its own colour class. The
  # computed colours are read at E2E.
  @impl true
  def study_card_colors_attributes?(context) do
    side_label(context.page, ".sifat-wajib-side") == ["SIFAT WAJIB"] and
      side_label(context.page, ".sifat-mustahil-side") == ["SIFAT MUSTAHIL"]
  end

  defp side_label(page, side) do
    page
    |> LazyHTML.query("[data-role=study-card] #{side} > span")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
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
    second_position = rendered_answer_position(context.page, "Hudus")

    is_integer(first_position) and is_integer(second_position) and
      first_position != second_position
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

  # The driver plays Codex: it answers only a prompt the LiveView's current session received
  # since the last answer, with events sent from that session to the LiveView's own
  # `handle_info/2`.
  defp answer_prompt(context, events) do
    {_prompt, context} = unanswered_prompt!(context)
    deliver_codex_events(context, events)
  end

  # The fixture Codex's own answer, decided from the session the prompt reached and the
  # prompts its conversation's thread answered before. The current session is the one the
  # LiveView opened last; a fresh one starts its own thread.
  defp stream_answer(context) do
    {prompt, context} = unanswered_prompt!(context)
    session = context.chat_socket.assigns.codex_session
    {:agent_session, :open, {thread_id, model, effort, _mode}} = last_open(context)

    unless thread_id == session.thread_id,
      do: raise("the current Codex session is not the conversation opened last")

    {events, threads} =
      CodexFixtureConversation.answer(
        Map.get(context, :codex_threads, %{}),
        %{
          thread_id: thread_id,
          new_thread_id: "fixture-thread-#{:erlang.phash2(session.ref)}",
          model: model,
          reasoning_effort: effort
        },
        prompt
      )

    context |> Map.put(:codex_threads, threads) |> deliver_codex_events(events)
  end

  defp unanswered_prompt!(context) do
    session = context.chat_socket.assigns.codex_session
    answered = Map.get(context, :answered_codex_calls, 0)

    context.codex_calls
    |> Enum.drop(answered)
    |> Enum.filter(&match?({:agent_session, :prompt, ^session, _}, &1))
    |> List.last()
    |> case do
      {:agent_session, :prompt, ^session, prompt} ->
        {prompt, Map.put(context, :answered_codex_calls, length(context.codex_calls))}

      nil ->
        raise "the current Codex session received no new prompt to answer"
    end
  end

  defp deliver_codex_events(context, events) do
    session = context.chat_socket.assigns.codex_session

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

  # The router's own route for "/family-chat", resolved without dispatching and run on a bare
  # conn, so the location is the one the controller answers rather than one this driver knows.
  defp family_chat_redirect_location do
    %{plug: controller, plug_opts: action} =
      Phoenix.Router.route_info(BnestAppWeb.Router, "GET", "/family-chat", "")

    {BnestAppWeb.FamilyChatController, :redirect_to_canonical} = {controller, action}
    response = apply(controller, action, [Plug.Test.conn(:get, "/family-chat"), %{}])
    {302, [location]} = {response.status, Plug.Conn.get_resp_header(response, "location")}
    location
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

  # The account is bootstrapped through the Identity facade on the browser request path, so
  # the login When can post the real login form and follow the session cookie home.
  def prepare_behaviour(context, state, _args)
      when state in [:approved_account, :approved_argon2_account] do
    username = "test-user-unit-login"
    context = start_request_path(context, [synthetic_account(username, ["admin"])])

    Map.merge(context, %{
      account_exists: true,
      identity_username: username,
      identity_password: @synthetic_password,
      verifier: stored_verifier(context.request_store, username)
    })
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

  # Two bootstrapped accounts, each owning a stored theme preference.
  def prepare_behaviour(context, :two_isolated_users, _args) do
    context =
      start_request_path(context, [
        synthetic_account("test-user-unit-first", ["admin"]),
        synthetic_account("test-user-unit-second", ["parents"])
      ])

    first = stored_account(context.request_store, "test-user-unit-first")
    second = stored_account(context.request_store, "test-user-unit-second")
    :ok = Preferences.put_theme(first["userId"], "light", @behaviour_now)
    :ok = Preferences.put_theme(second["userId"], "dark", @behaviour_now)
    second_theme = Preferences.theme(second["userId"])
    _setup = drain_record_accesses()

    Map.merge(context, %{
      first_user: first,
      second_owner: second["userId"],
      second_theme_before: second_theme
    })
  end

  # Each Given only fills the browser's storage report; the import page decides what to do
  # with every source when the user confirms.
  def prepare_behaviour(context, :recognized_browser_sources, _args),
    do:
      central_request_context(
        context,
        Enum.map(recognized_browser_sources(), &Map.put(&1, "present", true))
      )

  def prepare_behaviour(context, :absent_theme_source, _args),
    do:
      central_request_context(context, [
        %{"storageArea" => "localStorage", "storageKey" => "phx:theme", "present" => false}
      ])

  # The server already holds an accepted chat record; the browser's chat key now holds
  # malformed data.
  def prepare_behaviour(context, :invalid_browser_source, _args) do
    malformed = %{chat_source() | "payload" => "{malformed"}
    context = central_request_context(context, [Map.put(malformed, "present", true)])
    {:ok, _accepted} = Storage.import_browser(context.central_owner, chat_source())
    _setup = drain_record_accesses()

    Map.put(
      context,
      :accepted_before,
      RecordBackend.read(context.central_store, :chat, context.central_owner)
    )
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

  # No pointer exists behind the Storage facade's in-memory ports.
  def prepare_behaviour(context, :no_storage_configuration, _args) do
    install_storage_ports!()

    unless Storage.adapter(:config_store).read() == {:error, :absent},
      do: raise("a storage pointer already exists")

    context
  end

  def prepare_behaviour(context, :storage_ui_not_visited, _args),
    do: Map.put(context, :storage_ui_visits, watch_storage_ui_visits())

  # The status the administrator's storage page rendered must say the migration never started.
  def prepare_behaviour(%{storage_page: page} = context, :migration_not_started, _args) do
    status =
      page
      |> LazyHTML.query("section[aria-label='Migration status'] strong")
      |> LazyHTML.text()

    unless status == "Not started", do: raise("storage migration already started: #{status}")
    Map.put(context, :migration_attempts, 0)
  end

  # The administrator's storage page: the production `StorageLive` mounted over the Storage
  # facade's in-memory ports, which hold no pointer, and rendered with its template.
  def prepare_behaviour(context, :admin_opened_storage_settings, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])

    socket = %Socket{
      view: StorageLive,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}, current_user: @unit_admin}
    }

    {:ok, socket} = StorageLive.mount(%{}, %{}, socket)

    Map.merge(context, %{
      storage_admin?: true,
      storage_config: nil,
      authenticated: true,
      storage_socket: socket,
      storage_page: render_storage_page(socket)
    })
  end

  # A fresh installation behind the Storage facade's in-memory ports: no pointer, no flat
  # source, and a migration ledger without a run.
  def prepare_behaviour(context, :empty_isolated_database, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])

    unless MigrationLedger.state().runs == [] and FlatSource.list(@in_memory_flat_root) == [],
      do: raise("the isolated database is not empty")

    context
  end

  # A flat-primary installation without a pointer, whose flat source tree behind the
  # Storage facade's FlatSource port lists the `z-` owner's theme before the `a-` owner's.
  def prepare_behaviour(context, :flat_primary_default_location, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])
    FlatSource.put_files(@in_memory_flat_root, sqlite_storage_fixture_files())
    Map.put(context, :flat_files_before, FlatSource.files(@in_memory_flat_root))
  end

  # The managed migration was interrupted after its first record write: the ledger holds the
  # path-first source's accepted item and nothing for the other.
  def prepare_behaviour(context, :migration_stopped_after_progress, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])
    [first, remaining] = context.flat_files_before |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    migration_id = FlatMigration.migration_id()
    MigrationLedger.interrupt_after(1)

    interrupted? =
      try do
        Storage.migrate(@in_memory_flat_root, false)
        false
      rescue
        _interruption in RuntimeError -> true
      end

    MigrationLedger.resume()
    ledger = MigrationLedger.state()

    unless interrupted? and match?(%{outcome: "accepted"}, ledger.items[{migration_id, first}]) and
             not Map.has_key?(ledger.items, {migration_id, remaining}),
           do: raise("the migration did not stop after its first accepted item")

    Map.merge(context, %{
      interrupted_ledger: ledger,
      first_migrated_path: first,
      remaining_path: remaining
    })
  end

  # A flat-primary installation behind the Storage facade's in-memory ports whose dry run
  # already passed: the flat store holds an account and its chat, learning and theme
  # records, the flat source tree holds the same records as files, and the managed migration
  # copied them into SQLite, with parity measured over every source. The account is
  # bootstrapped through the Identity facade, which works on the record store Storage
  # reports as active.
  def prepare_behaviour(context, :all_verification_checks_pass, _args) do
    install_storage_ports!()
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

    FlatSource.put_files(@in_memory_flat_root, flat_source_files(flat))

    unless match?(
             {:ok, :dry_run, %{run: %{blocked: 0}}},
             Storage.migrate(@in_memory_flat_root, false)
           ) and StorageMigration.parity_ok?(@in_memory_flat_root),
           do: raise("the backfill does not match the flat sources")

    {_backend, sqlite} = Storage.record_backend()

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

  # A malformed theme source joins the flat-primary installation's tree.
  def prepare_behaviour(context, :malformed_or_changed_source, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])
    malformed = {"users/user-test-b-fixture/preferences/theme.json", ~s({"schemaVersion":99})}
    FlatSource.put_files(@in_memory_flat_root, context.flat_files_before ++ [malformed])

    Map.merge(context, %{
      malformed_source: malformed,
      flat_files_before: FlatSource.files(@in_memory_flat_root)
    })
  end

  def prepare_behaviour(context, :non_admin_family_member, _args),
    do: prepare_behaviour(context, :denied_settings_visitor, [])

  # A connected chat client over SQLite-primary storage, served by release revision A from
  # the blue slot: the production LiveView runs over the routed record repository with the
  # named Identity process beside it. The user's message was answered and saved, which is
  # the acknowledged state, and a draft is typed into the composer.
  def prepare_behaviour(context, :healthy_route_with_acknowledged_state, _args) do
    release = InMemoryReleaseEnvironment.new()
    InMemoryReleaseEnvironment.put_revision(release, "revision-a")
    InMemoryReleaseEnvironment.put_slot(release, "blue")

    context =
      context
      |> Map.put(:chat_storage, config: %{"schemaVersion" => 1, "phase" => "sqlite_primary"})
      |> open("/chat")
      |> send_message(@acknowledged_message)
      |> stream_answer()

    ExUnit.Callbacks.start_supervised!(Identity)

    context
    |> type_draft("unsent draft")
    |> Map.merge(%{release_environment: release, routed_health_before: Operations.readiness()})
  end

  # Authoritative SQLite in the legacy configuration directory behind the Storage facade's
  # in-memory ports: the pointer was persisted there and the managed migration activated
  # SQLite over the synthetic flat sources, beside a tracked placeholder.
  def prepare_behaviour(context, :legacy_authoritative_sqlite, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])

    FlatSource.put_files(@in_memory_flat_root, [
      {".gitkeep", ""} | sqlite_storage_fixture_files()
    ])

    legacy = StorageLocation.config_directory()
    {:ok, _config} = Storage.persist_directory(legacy)

    unless match?({:ok, :activated, _report}, Storage.migrate(@in_memory_flat_root, true)),
      do: raise("SQLite did not become authoritative in the legacy directory")

    Map.merge(context, %{
      legacy_database_directory: legacy,
      relocation_destination: Storage.default_directory()
    })
  end

  # The relocated database is the one the pointer names at its new generation.
  def prepare_behaviour(context, :routed_storage_generation_proven, _args) do
    context = prepare_behaviour(context, :legacy_authoritative_sqlite, [])
    {:ok, config} = Storage.relocate(context.relocation_destination)

    unless Storage.database_generation() == config["databaseGeneration"],
      do: raise("the pointer does not name the relocated generation")

    Map.merge(context, %{
      storage_generation: config["databaseGeneration"],
      storage_config_before_cleanup: config
    })
  end

  # Nothing is saved in the scenario's in-memory backup configuration store
  # (`UnitSupport`), whose synthetic repository holds the default folder.
  def prepare_behaviour(context, :no_backup_override, _args) do
    store = InMemoryBackupConfigStore.new()
    {:error, :absent} = InMemoryBackupConfigStore.read(store)
    Map.put(context, :repository_root, InMemoryBackupConfigStore.repository_root(store))
  end

  # The Scheduler's schedules live in the scenario's in-memory schedule store
  # (`UnitSupport`), put there as the release seeds put them.
  # The administrator's schedules page is mounted with the backup folder form it renders;
  # its save queues the first backup under the Scheduler's task supervisor.
  def prepare_behaviour(context, :admin_opened_schedules, _args) do
    key = "prod-sqlite-backup-daily"
    :ok = put_schedule!(key, "prod_sqlite_backup", "admin_system")
    ExUnit.Callbacks.start_supervised!({Task.Supervisor, name: BnestApp.Scheduler.Tasks})

    socket = %Socket{
      view: AdminScheduleSettingsLive,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}, current_user: @unit_admin}
    }

    {:ok, socket} = AdminScheduleSettingsLive.mount(%{}, %{}, socket)

    [_field] =
      socket
      |> render_schedules_page()
      |> LazyHTML.query(
        "form[phx-submit=save_backup] input[name='backup[destination_directory]']"
      )
      |> Enum.to_list()

    Map.merge(context, %{
      backup_directory: unit_backup_directory("override"),
      schedule_key: key,
      schedules_socket: socket
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

  # The setup claim of a destination saved through the Backup facade, as saving it on the
  # admin schedules page queues it.
  def prepare_behaviour(context, :accepted_backup_claim, _args) do
    key = "prod-sqlite-backup-daily"
    :ok = put_schedule!(key, "prod_sqlite_backup", "admin_system")
    {:ok, location} = Backup.save_destination(unit_backup_directory("authoritative"))
    {:ok, claim} = Scheduler.claim_setup(key, location.destination_id, @behaviour_now)
    Map.merge(context, %{backup_claim: claim, backup_location: location})
  end

  def prepare_behaviour(context, :overlapping_coordinators, _args) do
    key = "unit-overlap"
    :ok = put_schedule!(key, "fixture", "family")
    Map.put(context, :schedule_key, key)
  end

  # A family schedule and the admin/system backup schedule, persisted in the Scheduler's
  # configured store as the release seeds and `BnestApp.Test.Seeds.Schedules` persist them.
  def prepare_behaviour(context, :contextual_schedules, _args) do
    family_key = "unit-contextual-family"
    :ok = put_schedule!("prod-sqlite-backup-daily", "prod_sqlite_backup", "admin_system")
    :ok = put_schedule!(family_key, "fixture", "family")

    Map.put(context, :persisted_schedules, %{
      family: family_key,
      admin_system: "prod-sqlite-backup-daily"
    })
  end

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

  # An unknown file beside the owned pairs, and a file of a previous destination, in the
  # scenario's in-memory artifact store.
  def prepare_behaviour(context, :retention_fixture, _args) do
    directory = unit_backup_directory("retention")
    unknown = directory <> "/keep-me.txt"
    previous = directory <> "-previous/previous-destination.txt"
    store = InMemoryArtifactStore.new()
    :ok = InMemoryArtifactStore.put_file(store, unknown, "synthetic-unowned")
    :ok = InMemoryArtifactStore.put_file(store, previous, "retain")
    :ok = put_schedule!("prod-sqlite-backup-daily", "prod_sqlite_backup", "admin_system")

    Map.merge(context, %{
      backup_directory: directory,
      unknown_backup_file: unknown,
      previous_destination_file: previous
    })
  end

  def prepare_behaviour(context, :second_family_handler, _args) do
    key = "unit-second-family"
    :ok = put_schedule!(key, "fixture", "family")
    Map.put(context, :schedule_key, key)
  end

  # The panels the contexts declare, and each owner's saved state: Storage's chosen database
  # location in its in-memory pointer store, and the backup schedule in the Scheduler's
  # in-memory store (the schedules-backups panel's daily fields live there).
  def prepare_behaviour(context, :typed_settings_panels, _args) do
    previous = StoragePorts.install(config: @configured_storage_pointer)
    ExUnit.Callbacks.on_exit(fn -> StoragePorts.restore(previous) end)
    :ok = put_schedule!("prod-sqlite-backup-daily", "prod_sqlite_backup", "admin_system")

    Map.merge(context, %{
      declared_panels: Operations.admin_panels(),
      allowlist_schedule_key: "prod-sqlite-backup-daily"
    })
  end

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

  # The unit layer's repository ignores nothing, as a test run's root is no git repository, so
  # the default destination, which must be ignored, is refused.
  def prepare_behaviour(context, :test_environment, _args) do
    :ok = InMemoryIgnoreCheck.put_ignored(InMemoryIgnoreCheck.new(), false)
    BackupIntegrity.prepare(context, :test_environment, [])
  end

  # A destination in the scenario's in-memory artifact store, saved as the configured one.
  def prepare_behaviour(context, state, args) when state in @integrity_destination_prepares do
    {:ok, location} = Backup.save_destination(unit_backup_directory("integrity"))

    context
    |> Map.merge(%{backup_directory: location.directory, backup_location: location})
    |> BackupIntegrity.prepare(state, args)
  end

  def prepare_behaviour(context, state, args) when state in @integrity_prepares,
    do: BackupIntegrity.prepare(context, state, args)

  # A configured destination in the scenario's in-memory artifact store, which the restore
  # drill reads and holds the artifacts it restores.
  def prepare_behaviour(context, state, args) when state in @drill_destination_prepares do
    {:ok, location} = Backup.save_destination(unit_backup_directory("restore-drill"))

    context
    |> Map.merge(%{backup_directory: location.directory, backup_location: location})
    |> RestoreDrill.prepare(state, args)
  end

  def prepare_behaviour(context, state, args) when state in @drill_prepares,
    do: RestoreDrill.prepare(context, state, args)

  # The administrator opened the page and its label stated that every retained backup is
  # present: where the checks that follow a save start.
  def prepare_behaviour(context, :label_opened_all_present, _args) do
    context =
      context
      |> prepare_behaviour(:label_destination, ["all_present"])
      |> open_label_page()

    unless IntegrityLabel.outcome?(context, :label_states_all_present, []),
      do: raise("the schedules page did not state that every retained backup is present")

    context
  end

  # A family member with a real session who is no administrator, beside a destination whose
  # artifact reads are counted.
  def prepare_behaviour(context, :label_denied_visitor, _args) do
    context
    |> prepare_behaviour(:denied_settings_visitor, [])
    |> prepare_behaviour(:label_destination, ["watched"])
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

  # The submissions are the evidence: each password missing a letter, number or punctuation
  # mark is submitted on its own first and must leave setup open, then the real accounts use
  # a three-character and a 131-character password, and each must log in afterwards.
  def perform_behaviour(context, :bootstrap_accounts, _args) do
    store = context.identity_store
    {rejections, first_result, second_result, logins} = submit_initial_accounts(store)

    Map.merge(context, %{
      bootstrap_rejections: rejections,
      bootstrap_first_result: first_result,
      bootstrap_second_result: second_result,
      bootstrap_logins: logins,
      bootstrap_status: Bootstrap.status(store)
    })
  end

  # The login form posts through the router to the session controller, and the session
  # cookie it sets opens home; both requests run with every log line captured.
  def perform_behaviour(context, :login, _args) do
    params = %{
      "login" => %{
        "username" => context.identity_username,
        "password" => context.identity_password
      }
    }

    # Phoenix's request logger attaches when its application starts, which `--no-start`
    # leaves to the test.
    {:ok, _apps} = Application.ensure_all_started(:phoenix)

    {{login_response, token, home_response}, log} =
      with_debug_log(fn ->
        response = dispatch_request(:post, "/login", nil, params)
        token = identity_cookie(response)
        {response, token, token && follow_redirect(response, token)}
      end)

    Map.merge(context, %{
      login_response: login_response,
      home_response: home_response,
      login_log: log,
      identity_token: token,
      authenticated: is_binary(token)
    })
  end

  def perform_behaviour(context, :logout_current_browser, _args) do
    response = dispatch_request(:delete, "/logout", context.identity_token)
    Map.merge(context, %{logout_response: response, authenticated: false})
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

  # The first user's theme read and write aimed at the second owner, each guarded by the
  # authorization a request handler applies before it reaches the Preferences facade. The
  # flat store's recorder reports every record access the attempt makes.
  def perform_behaviour(context, :cross_user_operation, _args) do
    attempts = cross_user_theme_attempts(context.first_user, context.second_owner)
    accesses = drain_record_accesses()

    Map.merge(context, %{
      cross_user_attempts: attempts,
      cross_user_accesses: accesses,
      second_theme_after: Preferences.theme(context.second_owner)
    })
  end

  # The import page's own handlers receive the browser's report and the confirmation; the
  # rendered outcome lines and the cleanup instruction pushed back are the user's evidence.
  def perform_behaviour(context, :confirm_imports, _args) do
    socket = %Socket{
      view: DataMigrationLive,
      assigns: %{__changed__: %{}, flash: %{}, current_user: %{"userId" => context.central_owner}}
    }

    {:noreply, socket} =
      DataMigrationLive.handle_event(
        "browser-sources",
        %{"sources" => context.browser_sources},
        socket
      )

    {:noreply, socket} = DataMigrationLive.handle_event("confirm-imports", %{}, socket)
    [["imports-accepted", %{"storageKeys" => cleared}]] = Utils.get_push_events(socket)

    outcomes =
      socket.assigns
      |> Map.delete(:__changed__)
      |> DataMigrationLive.render()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[aria-live=polite] p")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    Map.merge(context, %{import_outcomes: outcomes, cleared_storage_keys: cleared})
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

  # The managed migration is the Storage facade's headless entry point, the one the
  # `bnest.storage.migrate` task calls: a dry run over one synthetic flat theme source.
  def perform_behaviour(context, :start_managed_migration, _args) do
    FlatSource.put_files(@in_memory_flat_root, Enum.take(sqlite_storage_fixture_files(), 1))
    visits_before = :counters.get(context.storage_ui_visits, 1)
    outcome = Storage.migrate(@in_memory_flat_root, false)

    Map.merge(context, %{
      migration_outcome: outcome,
      storage_calls: StoragePorts.calls(),
      storage_ui_visits_during_migration:
        :counters.get(context.storage_ui_visits, 1) - visits_before
    })
  end

  # Relocation runs through the Storage facade; only the calls it made are kept.
  def perform_behaviour(context, :relocate_storage, _args) do
    calls_before = length(StoragePorts.calls())
    result = Storage.relocate(context.relocation_destination)

    Map.merge(context, %{
      relocation_result: result,
      relocation_calls: Enum.drop(StoragePorts.calls(), calls_before)
    })
  end

  def perform_behaviour(context, :retire_legacy_storage, _args),
    do:
      Map.put(
        context,
        :retirement_result,
        Storage.retire(@in_memory_flat_root, context.storage_generation, false)
      )

  # The administrator's folder, written unnormalized, through the production persist path
  # with the real location rules over a synthetic private folder.
  def perform_behaviour(
        %{
          authenticated: true,
          migration_attempts: 0,
          storage_admin?: true,
          storage_config: nil
        } = context,
        :enter_valid_folder,
        _args
      ) do
    candidate = "/srv/test-user-storage/../test-user-storage/custom/"

    filesystem = %{
      lstat: fn _path -> {:error, :enoent} end,
      stat: fn
        "/srv/test-user-storage/custom" -> {:ok, %{mode: 0o700}}
        "/srv/test-user-storage" -> {:ok, %{mode: 0o755}}
        _path -> {:error, :enoent}
      end
    }

    {persist_result, storage_pointer} = persist_with_pointer(candidate, filesystem)

    Map.merge(context, %{
      requested_directory: candidate,
      normalized_directory: "/srv/test-user-storage/custom",
      persist_result: persist_result,
      storage_pointer: storage_pointer
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
      normalized_directory: candidate,
      persist_result: persist_result,
      storage_pointer: storage_pointer
    })
  end

  # The storage page's create action receives a relative folder and one inside the
  # repository; the correction each rendered is kept, with the port calls they caused.
  def perform_behaviour(%{storage_socket: socket} = context, :enter_unsafe_folder, _args) do
    inside_repository = __DIR__ <> "/../../../test-user-storage"

    corrections =
      Enum.map(["relative/storage", inside_repository], fn directory ->
        {:noreply, socket} =
          StorageLive.handle_event("create_database", %{"directory" => directory}, socket)

        socket
        |> render_storage_page()
        |> LazyHTML.query("[role=alert]")
        |> LazyHTML.text()
        |> String.trim()
      end)

    Map.merge(context, %{storage_corrections: corrections, storage_calls: StoragePorts.calls()})
  end

  # The managed migration starts twice; each start applies the committed schema.
  def perform_behaviour(context, :apply_migration_set_twice, _args) do
    first = Storage.migrate(@in_memory_flat_root, false)
    ledger_after_first = MigrationLedger.state()
    second = Storage.migrate(@in_memory_flat_root, false)

    Map.merge(context, %{
      schema_applies: [first, second],
      ledger_after_first_apply: ledger_after_first,
      ledger_after_second_apply: MigrationLedger.state(),
      storage_calls: StoragePorts.calls()
    })
  end

  def perform_behaviour(context, :run_managed_storage_migration, _args) do
    outcome = Storage.migrate(@in_memory_flat_root, false)

    Map.merge(context, %{
      migration_outcome: outcome,
      migration_ledger: MigrationLedger.state(),
      storage_calls: StoragePorts.calls()
    })
  end

  # The retry is the same managed migration; the SQLite store is read around it.
  def perform_behaviour(context, :retry_same_migration, _args) do
    {_backend, sqlite} = Storage.record_backend()
    before = InMemoryRecordBackend.snapshot(sqlite)
    outcome = Storage.migrate(@in_memory_flat_root, false)

    Map.merge(context, %{
      migration_outcome: outcome,
      migration_ledger: MigrationLedger.state(),
      sqlite_before_retry: before,
      sqlite_after_retry: InMemoryRecordBackend.snapshot(sqlite)
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

  # Verification is the managed migration with the authority switch requested.
  def perform_behaviour(context, :verify_migration, _args) do
    outcome = Storage.migrate(@in_memory_flat_root, true)

    Map.merge(context, %{
      migration_outcome: outcome,
      migration_ledger: MigrationLedger.state(),
      storage_calls: StoragePorts.calls()
    })
  end

  # The visitor's browser asks the router for the storage page with its own session cookie.
  def perform_behaviour(context, :open_storage_settings_route, _args) do
    {response, accesses} = route_request("/storage", context.visitor_token)
    Map.merge(context, %{storage_response: response, storage_accesses: accesses})
  end

  # Promotion swaps the routed release under the client: the candidate serves revision B
  # from the green slot, the LiveView terminates and the record repository restarts, and
  # the client mounts its route again and replays its draft through the form's recovery
  # event.
  def perform_behaviour(context, :promote_compatible_candidate, _args) do
    InMemoryReleaseEnvironment.put_revision(context.release_environment, "revision-b")
    InMemoryReleaseEnvironment.put_slot(context.release_environment, "green")

    context
    |> Map.put(:chat_socket_before_promotion, context.chat_socket)
    |> reconnect()
    |> then(&Map.put(&1, :routed_health_after, Operations.readiness()))
  end

  # The destination resolves through the Backup facade, and its setup claim runs the
  # registered Backup task through the Scheduler; the verified result is the receipt the
  # destination then owns.
  def perform_behaviour(context, :resolve_backup_destination, _args) do
    {:ok, location} = result = Backup.destination()
    key = "prod-sqlite-backup-daily"
    :ok = put_schedule!(key, "prod_sqlite_backup", "admin_system")
    {:ok, claim} = Scheduler.claim_setup(key, location.destination_id, @behaviour_now)
    :ok = Scheduler.execute(claim, @behaviour_now)

    Map.merge(context, %{
      backup_resolution: result,
      backup_receipts: Backup.owned_receipts(location.directory)
    })
  end

  # The administrator submits the page's backup folder form twice with the same folder, as
  # a double click would; the first verification each save queues runs to completion.
  def perform_behaviour(context, :save_backup_override, _args) do
    params = %{"backup" => %{"destination_directory" => context.backup_directory}}

    socket =
      Enum.reduce(1..2, context.schedules_socket, fn _submit, socket ->
        {:noreply, socket} = AdminScheduleSettingsLive.handle_event("save_backup", params, socket)
        socket
      end)

    await_scheduler_tasks()

    Map.merge(context, %{
      schedules_page: render_schedules_page(socket),
      backup_destination: Backup.destination()
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
      reconciled_claims: Enum.filter(claims, &(&1.schedule_key == context.schedule_key)),
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

  # The accepted claim runs the registered Backup task through the Scheduler; what it
  # produced is read back from the destination it owns.
  def perform_behaviour(context, :run_backup_handler, _args) do
    :ok = Scheduler.execute(context.backup_claim, @behaviour_now)
    Map.put(context, :backup_receipts, Backup.owned_receipts(context.backup_location.directory))
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

  def perform_behaviour(context, :open_schedules_from_home, _args),
    do: Map.put(context, :page, follow_admin_entry("admin-schedules-entry"))

  def perform_behaviour(context, :open_admin_settings, _args) do
    {response, accesses} = route_request("/admin/settings", context.visitor_token)
    Map.merge(context, %{settings_response: response, settings_accesses: accesses})
  end

  # Nine daily setup runs of the saved destination, oldest first, each through the
  # Scheduler's registered Backup task, which applies retention once its backup is
  # verified. Each receipt is read while it is the destination's newest.
  def perform_behaviour(context, :verify_new_backup, _args) do
    {:ok, location} = Backup.save_destination(context.backup_directory)

    receipts =
      Enum.map(8..0//-1, fn days ->
        at = DateTime.add(@behaviour_now, -days * 86_400)

        {:ok, claim} =
          Scheduler.claim_setup(
            "prod-sqlite-backup-daily",
            "#{location.destination_id}-#{days}",
            at
          )

        :ok = Scheduler.execute(claim, at)
        [%{"runId" => run_id} = receipt | _older] = Backup.owned_receipts(location.directory)
        ^run_id = claim.run_id
        receipt
      end)

    Map.put(context, :retention_receipts, Enum.reverse(receipts))
  end

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

  def perform_behaviour(context, :open_admin_settings_from_home, _args),
    do: Map.put(context, :page, follow_admin_entry("admin-settings-entry"))

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

  # The reconcile task over the unit layer's adapters: the ledger's verified runs, the
  # destination read through the artifact store, the one wording function.
  # The page as a connected administrator opens it: the first render, then the render once
  # the check it started has reported (`IntegrityLabel.settle/1`).
  def perform_behaviour(context, :open_schedules_label, args),
    do: context |> open_label_page() |> note_viewport(args)

  # One of the page's forms submitted with the fields as rendered: the label is read right
  # after the event and again once the check the save started has reported.
  def perform_behaviour(context, :save_label_form, [form]) do
    socket = context.schedules_socket
    {event, params} = label_form(render_schedules_page(socket), form)
    {:noreply, saved} = AdminScheduleSettingsLive.handle_event(event, params, socket)
    after_save = render_schedules_page(saved)
    settled = IntegrityLabel.settle(saved)
    await_scheduler_tasks()

    Map.merge(context, %{
      schedules_socket: settled,
      label_after_save: after_save,
      label_settled_after_save: render_schedules_page(settled)
    })
  end

  def perform_behaviour(context, :open_and_reload_label, []) do
    evidence = %{
      destination: BackupIntegrity.snapshot(context.backup_directory),
      ledger: BackupIntegrity.ledger_rows()
    }

    context |> open_label_page() |> open_label_page() |> Map.put(:evidence_before, evidence)
  end

  def perform_behaviour(context, :read_label_and_report, []) do
    context
    |> open_label_page()
    |> BackupIntegrity.run_task(&reconcile_task/0)
  end

  # The page is opened over a check that never finishes: the first render is read at once,
  # and the result only when the page's ceiling ends the check.
  def perform_behaviour(context, :open_label_past_ceiling, []) do
    started = IntegrityLabel.now()
    socket = mount_schedules_page()
    first = render_schedules_page(socket)
    settled = IntegrityLabel.settle(socket)
    elapsed = IntegrityLabel.now() - started

    Map.merge(context, %{
      schedules_socket: settled,
      label_first: first,
      label_page: render_schedules_page(settled),
      ceiling: IntegrityLabel.observe_ceiling(elapsed)
    })
  end

  # The visitor's request is stopped by the router's admin guard. The artifact reads it
  # caused are counted, and so are the reads of an administrator's visit to the same route:
  # the probe sees a reconciliation when one runs, so no reads for the visitor is a measurement.
  def perform_behaviour(context, :open_schedules_route_denied, []) do
    reads = ObservedArtifactStore.read_count()
    {response, accesses} = route_request("/admin/settings/schedules", context.visitor_token)
    denied = ObservedArtifactStore.read_count() - reads

    reads = ObservedArtifactStore.read_count()
    _control = open_label_page(context)
    control = ObservedArtifactStore.read_count() - reads

    Map.merge(context, %{
      settings_response: response,
      settings_accesses: accesses,
      denied_reads: denied,
      control_reads: control
    })
  end

  # The reconcile task's own entry point over the scenario's in-memory ledger and destination.
  def perform_behaviour(context, :reconcile_task, _args),
    do: BackupIntegrity.run_task(context, &reconcile_task/0)

  def perform_behaviour(context, :read_report_and_log, _args),
    do: BackupIntegrity.read_report_and_log(context, &reconcile_task/0)

  def perform_behaviour(context, action, args) when action in @integrity_performs,
    do: BackupIntegrity.perform(context, action, args)

  def perform_behaviour(context, action, args) when action in @drill_performs,
    do: RestoreDrill.perform(context, action, args)

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
    do: accepted_any_length?(context)

  def behaviour_outcome?(context, :password_requirements_enforced, _args),
    do: rejected_each_missing_requirement?(context.bootstrap_rejections)

  def behaviour_outcome?(context, :protected_home_available, _args),
    do: protected_home?(context.home_response)

  # The logout went through the router; reopening home with the same cookie must redirect to
  # login, and the session it named must be gone.
  def behaviour_outcome?(context, :current_browser_logged_out, _args) do
    {reopened, _accesses} = route_request("/", context.identity_token)

    redirects_to_login?(context.logout_response) and login_redirect(reopened) != nil and
      Identity.current_user(context.identity_token) == {:error, :unauthenticated}
  end

  # The unit layer hashes through the in-memory credential hasher, so it proves the
  # application's part: the account keeps the configured hasher's verifier, which checks the
  # password, and neither the stored records, the log captured at debug level across the
  # login request and the home request, nor either response holds the plaintext. That the
  # verifier is Argon2id is the real hasher's property, which the integration driver proves.
  def behaviour_outcome?(context, :no_plaintext_password, _args) do
    password = context.identity_password
    records = context.request_store |> InMemoryRecordBackend.snapshot() |> inspect()
    hasher = Identity.adapter(:credential_hasher)
    rendered = context.login_response.resp_body <> context.home_response.resp_body

    protected_home?(context.home_response) and
      String.contains?(context.login_log, "Processing with BnestAppWeb.SessionController.create") and
      context.verifier != password and hasher.verify(password, context.verifier) and
      not String.contains?(records, password) and
      not String.contains?(context.login_log, password) and
      not String.contains?(rendered, password)
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

  # Both attempts are denied, the recorder saw no access to any record of the second owner,
  # and the second owner's theme is what it was.
  def behaviour_outcome?(context, :denied_before_repository, _args) do
    owner = context.second_owner

    context.cross_user_attempts == [read_theme: :denied, write_theme: :denied] and
      not Enum.any?(context.cross_user_accesses, &owner_access?(&1, owner)) and
      context.second_theme_after == context.second_theme_before and
      context.second_theme_before == "dark"
  end

  # The migration wrote the pointer once through the pointer port, which keeps it in the
  # configuration home and outside the database directory the pointer names.
  def behaviour_outcome?(context, :pointer_under_configuration_home, _args) do
    store = Storage.adapter(:config_store)
    pointer = store.pointer_path()

    case Enum.filter(context.storage_calls, &match?({:write_config, _config}, &1)) do
      [{:write_config, config}] ->
        String.ends_with?(pointer, "/.config/bnest/storage.json") and
          store.read() == {:ok, config} and
          not String.starts_with?(pointer, config["databaseDirectory"] <> "/")

      _writes ->
        false
    end
  end

  # The unit layer runs under a test storage profile, whose data directory is the run's own.
  def behaviour_outcome?(context, :sqlite_under_production_data, _args) do
    database = profile_database_path()
    {:ok, config} = Storage.adapter(:config_store).read()

    config["databaseDirectory"] <> "/bnest.sqlite3" == database and
      String.contains?(database, "/bnest/data/test/runs/") and
      Enum.drop_while(context.storage_calls, &(&1 != {:ensure_started, database})) |> Enum.at(1) ==
        :migrate_schema
  end

  def behaviour_outcome?(context, :no_browser_confirmation, _args),
    do:
      match?(
        {:ok, :dry_run, %{run: %{accepted: 1, blocked: 0}, verification: nil}},
        context.migration_outcome
      ) and context.storage_ui_visits_during_migration == 0

  def behaviour_outcome?(
        %{storage_pointer: pointer} = context,
        :folder_normalized_with_fixed_filename,
        _args
      ) do
    stored = Agent.get(pointer, & &1)

    context.persist_result == {:ok, stored} and
      stored["databaseDirectory"] == context.normalized_directory and
      stored["databaseFilename"] == "bnest.sqlite3"
  end

  def behaviour_outcome?(
        %{storage_pointer: pointer} = context,
        :validated_location_stored_privately,
        _args
      ) do
    stored = Agent.get(pointer, & &1)

    Enum.sort(Map.keys(stored)) ==
      Enum.sort(~w(databaseDirectory databaseFilename migrationId phase schemaVersion)) and
      String.starts_with?(stored["databaseDirectory"], "/") and
      stored["databaseDirectory"] == context.normalized_directory
  end

  # Each refusal names its own correction: the relative folder and the folder inside the
  # repository are refused for different reasons, and neither gets the generic fallback.
  def behaviour_outcome?(context, :safe_correction_explained, _args),
    do:
      context.storage_corrections == [
        "Enter an absolute server-local folder.",
        "That folder overlaps the application or a migration source."
      ]

  def behaviour_outcome?(context, :no_storage_created, _args),
    do:
      Storage.adapter(:config_store).read() == {:error, :absent} and
        not Enum.any?(context.storage_calls, fn call ->
          match?({:write_config, _config}, call) or match?({:ensure_started, _path}, call) or
            call == :migrate_schema
        end)

  # The run records the checksum of the committed schema sources the database lifecycle
  # applies, computed here independently over the same sources, and both starts applied
  # the schema.
  def behaviour_outcome?(context, :schema_matches_checksum, _args) do
    checksum =
      :sha256
      |> :crypto.hash(Enum.join(Storage.adapter(:database_lifecycle).schema_sources()))
      |> Base.encode16(case: :lower)

    match?(
      [%{migration_id: "flat-files-v1-to-sqlite-v1", ddl_checksum: ^checksum}],
      context.ledger_after_first_apply.runs
    ) and Enum.count(context.storage_calls, &(&1 == :migrate_schema)) == 2 and
      Enum.all?(context.schema_applies, &match?({:ok, :dry_run, _report}, &1))
  end

  # The second start records no second run and leaves the first run's schema checksum.
  def behaviour_outcome?(context, :no_duplicate_schema_objects, _args) do
    %{runs: first_runs} = context.ledger_after_first_apply
    %{runs: second_runs, writes: writes} = context.ledger_after_second_apply

    length(second_runs) == 1 and
      Enum.map(second_runs, & &1.ddl_checksum) ==
        Enum.map(first_runs, & &1.ddl_checksum) and
      Enum.count(writes, &match?({:start_run, _migration_id}, &1)) == 1
  end

  # The source tree lists `z-` before `a-`, so only a path-ordered inventory records this
  # order.
  def behaviour_outcome?(context, :deterministic_inventory, _args) do
    path_order = [
      "users/user-test-a-fixture/preferences/theme.json",
      "users/user-test-z-fixture/preferences/theme.json"
    ]

    recorded = for {:put_item, path, _outcome} <- context.migration_ledger.writes, do: path
    FlatSource.list(@in_memory_flat_root) == Enum.reverse(path_order) and recorded == path_order
  end

  # The database the migration started and migrated is the one under the profile's data
  # directory, which the pointer now resolves.
  def behaviour_outcome?(context, :database_under_resolved_directory, _args) do
    database = profile_database_path()

    Storage.database_path() == database and
      Enum.drop_while(context.storage_calls, &(&1 != {:ensure_started, database})) |> Enum.at(1) ==
        :migrate_schema
  end

  def behaviour_outcome?(context, :all_valid_items_accepted, _args) do
    count = length(context.flat_files_before)

    match?(
      {:ok, :dry_run, %{run: %{accepted: ^count, blocked: 0, unsupported: 0}}},
      context.migration_outcome
    ) and
      Enum.all?(Map.values(context.migration_ledger.items), &(&1.outcome == "accepted")) and
      map_size(context.migration_ledger.items) == count
  end

  # Each item's source checksum is the source bytes' digest, computed here, and its target
  # checksum is the stored record's canonical digest; the sources stay as they were.
  def behaviour_outcome?(context, :checksum_evidence_present, _args) do
    {_backend, sqlite} = Storage.record_backend()

    FlatSource.files(@in_memory_flat_root) == context.flat_files_before and
      Enum.all?(context.flat_files_before, fn {path, bytes} ->
        with %{outcome: "accepted", source_sha256: source, target_sha256: target} <-
               context.migration_ledger.items[{FlatMigration.migration_id(), path}],
             {:ok, record} <- RecordBackend.read(sqlite, :theme, theme_owner(path)) do
          source == :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower) and
            target == CanonicalJson.sha256(record)
        else
          _missing -> false
        end
      end)
  end

  # The SQLite record backend the Storage facade hands out returns each source's record,
  # which the record schema validates unchanged.
  def behaviour_outcome?(context, :normal_reads_match, _args) do
    {_backend, sqlite} = Storage.record_backend()

    Enum.all?(context.flat_files_before, fn {path, bytes} ->
      record = Jason.decode!(bytes)

      RecordBackend.read(sqlite, :theme, theme_owner(path)) == {:ok, record} and
        Storage.validate_record(record) == {:ok, record}
    end)
  end

  # The retry wrote nothing for the item the interrupted pass accepted: no ledger item, no
  # record, no second run, and the stored record and item are as they were.
  def behaviour_outcome?(context, :accepted_items_not_duplicated, _args) do
    first = context.first_migrated_path
    owner = theme_owner(first)
    key = {FlatMigration.migration_id(), first}

    retry_writes =
      Enum.drop(context.migration_ledger.writes, length(context.interrupted_ledger.writes))

    context.migration_ledger.items[key] == context.interrupted_ledger.items[key] and
      not Enum.any?(retry_writes, fn write ->
        match?({:put_item, ^first, _outcome}, write) or write == {:put_record, :theme, owner} or
          match?({:start_run, _migration_id}, write)
      end) and
      Map.fetch!(context.sqlite_after_retry, {:theme, owner}) ==
        Map.fetch!(context.sqlite_before_retry, {:theme, owner}) and
      length(context.migration_ledger.runs) == 1
  end

  # The retry assessed and copied the remaining source exactly once.
  def behaviour_outcome?(context, :remaining_items_continue, _args) do
    remaining = context.remaining_path

    retry_writes =
      Enum.drop(context.migration_ledger.writes, length(context.interrupted_ledger.writes))

    Enum.filter(retry_writes, &match?({:put_item, ^remaining, _outcome}, &1)) ==
      [{:put_item, remaining, "accepted"}] and
      Enum.count(retry_writes, &(&1 == {:put_record, :theme, theme_owner(remaining)})) == 1 and
      match?({:ok, :dry_run, %{run: %{accepted: 2, blocked: 0}}}, context.migration_outcome)
  end

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

  # The switch was attempted and refused, so the pointer never left the flat phase.
  def behaviour_outcome?(context, :sqlite_not_authoritative, _args),
    do:
      match?({:error, :blocked, %{verification: nil}}, context.migration_outcome) and
        Storage.phase() == :flat_primary and
        Enum.all?(context.storage_calls, fn
          {:write_config, config} -> config["phase"] == "flat_primary"
          _call -> true
        end)

  # Every source keeps its bytes, and the malformed one reached no SQLite record.
  def behaviour_outcome?(context, :source_and_service_unchanged, _args) do
    {path, _bytes} = context.malformed_source
    {_backend, sqlite} = Storage.record_backend()

    FlatSource.files(@in_memory_flat_root) == context.flat_files_before and
      RecordBackend.read(sqlite, :theme, theme_owner(path)) == {:error, :missing}
  end

  # The run failed, and the blocked item carries a category naming neither its path, its
  # owner, nor its bytes.
  def behaviour_outcome?(context, :value_free_retry_category, _args) do
    {path, bytes} = context.malformed_source

    case context.migration_ledger.items[{FlatMigration.migration_id(), path}] do
      %{outcome: "invalid", error_category: "malformed" = category} ->
        match?(
          {:error, :blocked, %{run: %{state: "failed", blocked: 1}}},
          context.migration_outcome
        ) and
          not String.contains?(category, [path, bytes, theme_owner(path)])

      _item ->
        false
    end
  end

  def behaviour_outcome?(context, :storage_access_denied, _args) do
    response = context.storage_response
    response.halted and response.status == 404 and response.resp_body == "Not found"
  end

  # The refusal names no storage location or flat source, and the request read nothing but
  # the visitor's own session and account.
  def behaviour_outcome?(context, :no_host_path_or_inventory_revealed, _args) do
    body = context.storage_response.resp_body
    own = [Identity.session_digest(context.visitor_token), context.visitor["userId"]]

    not String.contains?(body, [
      Storage.database_path(),
      Storage.default_directory(),
      "bnest.sqlite3",
      "users/",
      "system/"
    ]) and
      Enum.all?(context.storage_accesses, fn {operation, _type, identity} ->
        operation == :read and identity in own
      end)
  end

  # Readiness names revision A from the blue slot before the promotion and revision B from
  # the green slot after it, with the Storage pointer keeping SQLite authoritative for the
  # records the chat reaches.
  def behaviour_outcome?(context, :routed_revision_and_readiness_proven, _args),
    do:
      match?(
        {:ok, %{status: "ready", revision: "revision-a", slot: "blue"}},
        context.routed_health_before
      ) and
        match?(
          {:ok, %{status: "ready", revision: "revision-b", slot: "green"}},
          context.routed_health_after
        ) and Storage.phase() == :sqlite_primary and
        Records.active_backend(context.chat_records) == Storage.record_backend()

  # The route is served by a fresh mount with its own Codex session, with no reload step.
  def behaviour_outcome?(context, :liveview_reconnects_without_refresh, _args),
    do:
      current_route?(context, "/chat") and
        context.chat_socket.assigns.codex_session !=
          context.chat_socket_before_promotion.assigns.codex_session

  # The acknowledged turn and the draft are read back out of the re-rendered page.
  def behaviour_outcome?(context, :acknowledged_state_and_draft_available, _args),
    do:
      visitor_message_visible?(context, @acknowledged_message) and
        one_completed_codex_response_visible?(context) and
        composer_contains?(context, "unsent draft")

  # One pointer write moved the database to the profile's data directory at a new
  # generation, which the pointer now resolves.
  def behaviour_outcome?(context, :pointer_relocated_atomically, _args) do
    {:ok, config} = Storage.adapter(:config_store).read()
    database = profile_database_path()

    context.relocation_result == {:ok, config} and
      config["databaseDirectory"] <> "/bnest.sqlite3" == database and
      Storage.database_path() == database and
      config["databaseGeneration"] not in [nil, ""] and
      Enum.count(context.relocation_calls, &match?({:write_config, _config}, &1)) == 1
  end

  def behaviour_outcome?(context, :legacy_sqlite_retained_until_proof, _args) do
    {:ok, config} = Storage.adapter(:config_store).read()

    config["legacyDatabaseDirectory"] == context.legacy_database_directory and
      Storage.phase() == :sqlite_primary and
      not Enum.any?(StoragePorts.calls(), &match?({:remove_legacy_database, _path}, &1))
  end

  # Only the placeholder is left of the flat tree, and the legacy database went with both
  # sidecars.
  def behaviour_outcome?(context, :verified_legacy_sources_removed, _args) do
    database = context.legacy_database_directory <> "/bnest.sqlite3"

    match?({:ok, %{"flatFilesRetiredAt" => _retired_at}}, context.retirement_result) and
      FlatSource.files(@in_memory_flat_root) == [{".gitkeep", ""}] and
      for({:remove_legacy_database, path} <- StoragePorts.calls(), do: path) ==
        [database, database <> "-wal", database <> "-shm"]
  end

  # The pointer keeps every setting but the retired legacy directory, and the placeholder
  # stays.
  def behaviour_outcome?(context, :config_and_placeholders_preserved, _args) do
    {:ok, config} = Storage.adapter(:config_store).read()

    Map.delete(config, "flatFilesRetiredAt") ==
      Map.delete(context.storage_config_before_cleanup, "legacyDatabaseDirectory") and
      {".gitkeep", ""} in FlatSource.files(@in_memory_flat_root)
  end

  # The page reported each source accepted, and the store holds one envelope per source,
  # each keeping the browser payload as given.
  def behaviour_outcome?(context, :immutable_envelopes, _args) do
    envelopes =
      for {{:browser_import, {owner, _import_id}}, envelope} <-
            InMemoryRecordBackend.snapshot(context.central_store),
          owner == context.central_owner,
          into: %{},
          do: {envelope["source"]["storageKey"], envelope}

    context.import_outcomes == [
      "Chat conversation: accepted and verified",
      "Sifat Allah progress: accepted and verified",
      "Theme preference: accepted and verified"
    ] and
      Enum.all?(context.browser_sources, fn source ->
        payload = source["payload"]

        match?(
          %{"payloadEncoding" => "utf8-string", "payload" => ^payload},
          envelopes[source["storageKey"]]
        )
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

  # The page reported the theme accepted with no browser key to clear, and the store holds
  # exactly one accepted browser-absence manifest for the owner's theme.
  def behaviour_outcome?(context, :absent_theme_recorded, _args) do
    manifests =
      for {{:manifest, _import_id}, manifest} <-
            InMemoryRecordBackend.snapshot(context.central_store),
          manifest["ownerId"] == context.central_owner,
          do: manifest

    context.import_outcomes == ["Theme preference: accepted and verified"] and
      context.cleared_storage_keys == [] and
      match?(
        [
          %{
            "status" => "accepted",
            "source" => %{"reference" => "phx:theme"},
            "recoverySource" => %{"kind" => "browser-absence"}
          }
        ],
        manifests
      )
  end

  def behaviour_outcome?(context, :no_theme_preference, _args),
    do:
      RecordBackend.read(context.central_store, :theme, context.central_owner) ==
        {:error, :missing}

  def behaviour_outcome?(context, :safe_rejected_import, _args),
    do: context.import_outcomes == ["Chat conversation: rejected safely; browser source retained"]

  # Nothing tells the browser to clear its key, and the server's accepted chat record is the
  # one it held before.
  def behaviour_outcome?(context, :source_and_record_unchanged, _args),
    do:
      context.cleared_storage_keys == [] and
        RecordBackend.read(context.central_store, :chat, context.central_owner) ==
          context.accepted_before and match?({:ok, _record}, context.accepted_before)

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

  # The destination is the repository's `data/backup`, which the repository ignores: the
  # ignore check was asked about exactly that folder.
  def behaviour_outcome?(context, :default_backup_folder, _args) do
    default = context.repository_root <> "/data/backup"

    match?({:ok, %{directory: ^default}}, context.backup_resolution) and
      InMemoryIgnoreCheck.checks(InMemoryIgnoreCheck.new())
      |> Enum.member?({context.repository_root, "data/backup"})
  end

  # The verified receipt names its destination only by id and its artifact only by basename;
  # neither the backup folder, the repository holding it, nor the live database path appears.
  def behaviour_outcome?(context, :no_private_path, _args) do
    with {:ok, location} <- context.backup_resolution,
         [receipt] <- context.backup_receipts,
         true <- Receipt.valid?(receipt, location.destination_id) do
      encoded = Jason.encode!(receipt)
      source = InMemoryDatabaseSnapshot.source_path(InMemoryDatabaseSnapshot.new())

      Enum.all?(
        [context.repository_root, location.directory, source],
        &(not String.contains?(encoded, &1))
      )
    else
      _failure -> false
    end
  end

  # One whole document was written, naming the saved destination, and the destination
  # now resolves to it.
  # Every write was one whole document naming the submitted folder, and the destination now
  # resolves to it.
  def behaviour_outcome?(context, :atomic_backup_config, _args) do
    store = InMemoryBackupConfigStore.new()
    document = %{"schemaVersion" => 1, "destinationDirectory" => context.backup_directory}
    writes = InMemoryBackupConfigStore.writes(store)
    directory = context.backup_directory

    writes != [] and Enum.all?(writes, &(&1 == document)) and
      InMemoryBackupConfigStore.document(store) == document and
      match?({:ok, %{directory: ^directory}}, context.backup_destination)
  end

  # The page confirmed the save, and the Scheduler's store holds exactly one run claimed for
  # the saved destination however often it was saved.
  def behaviour_outcome?(context, :one_setup_claim, _args) do
    {:ok, %{destination_id: destination_id}} = context.backup_destination

    setup_runs =
      Scheduler.store()
      |> InMemoryScheduleStore.runs()
      |> Enum.filter(&(&1.claim_key == "setup:" <> destination_id))

    String.contains?(
      LazyHTML.text(context.schedules_page),
      "Backup folder saved and its first verification was queued."
    ) and length(setup_runs) == 1
  end

  def behaviour_outcome?(context, :schedule_persisted, _args),
    do: context.scheduler_restarted? and context.schedule_after_restart.enabled

  def behaviour_outcome?(context, :same_future_slot, _args),
    do: context.schedule_after_restart.next_run_at == context.schedule_before_restart.next_run_at

  # Exactly one claim came back for the schedule, for its latest slot, and the store holds
  # no other run for it.
  def behaviour_outcome?(context, :latest_slot_only, _args) do
    latest = Policy.latest_slot(context.reconciled_schedule.daily_at_utc, @behaviour_now)

    stored =
      Scheduler.store()
      |> InMemoryScheduleStore.runs()
      |> Enum.filter(&(&1.schedule_key == context.schedule_key))

    match?([%{scheduled_for: ^latest}], context.reconciled_claims) and
      match?([%{scheduled_for: ^latest}], stored)
  end

  def behaviour_outcome?(context, :next_future_day, _args),
    do:
      context.reconciled_schedule.next_run_at ==
        Policy.next_slot(context.reconciled_schedule.daily_at_utc, @behaviour_now)

  # The one snapshot taken copied the configured live database: its generation is the
  # receipt's, and the artifact the receipt names is present in the destination.
  def behaviour_outcome?(context, :authoritative_vacuum, _args) do
    snapshot = InMemoryDatabaseSnapshot.new()

    case context.backup_receipts do
      [%{"artifactBasename" => basename} = receipt] ->
        artifact = context.backup_location.directory <> "/" <> basename

        receipt["sourceGeneration"] == InMemoryDatabaseSnapshot.source_generation(snapshot) and
          InMemoryDatabaseSnapshot.snapshots(snapshot) == [artifact <> ".partial"] and
          InMemoryArtifactStore.regular?(InMemoryArtifactStore.new(), artifact)

      _none_or_several ->
        false
    end
  end

  # The candidate was proved on its own before promotion, and the receipt records that
  # proof for the destination that owns it.
  def behaviour_outcome?(context, :independent_proof, _args) do
    case context.backup_receipts do
      [
        %{"artifactBasename" => basename, "quickCheck" => "ok", "logicalProofSha256" => proof} =
            receipt
      ]
      when byte_size(proof) == 64 ->
        partial = context.backup_location.directory <> "/" <> basename <> ".partial"

        InMemoryDatabaseSnapshot.proofs(InMemoryDatabaseSnapshot.new()) == [partial] and
          Receipt.valid?(receipt, context.backup_location.destination_id)

      _unproved ->
        false
    end
  end

  def behaviour_outcome?(context, :single_nonoverlap_claim, _args),
    do: length(context.overlap_claims) == 1

  def behaviour_outcome?(context, :bounded_attempts, _args),
    do:
      Enum.map(context.retry_attempts, & &1.attempt) == [2, 3, 3] and
        List.last(context.retry_attempts).state == "failed"

  # Read from the rendered page: each persisted schedule is one row of its own context's
  # group, and the family row shows a safe status, as the FE e2e reads it.
  def behaviour_outcome?(context, :context_groups, _args) do
    %{family: family, admin_system: admin_system} = context.persisted_schedules
    family_row = schedule_row(context.page, "family-schedules-title", family)

    Enum.count(family_row) == 1 and
      family_row |> LazyHTML.text() |> String.match?(@safe_schedule_status) and
      Enum.count(schedule_row(context.page, "admin-schedules-title", admin_system)) == 1
  end

  def behaviour_outcome?(context, :typed_backup_link, _args),
    do:
      context.page
      |> LazyHTML.query(~s([data-schedule-key="prod-sqlite-backup-daily"] a))
      |> LazyHTML.attribute("href")
      |> Kernel.==(["/admin/settings/schedules"])

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

  # Nine runs fell on nine WIB dates: the destination owns the seven newest pairs, and the
  # two oldest are gone from it, artifact and receipt both.
  def behaviour_outcome?(context, :owned_retention, _args) do
    store = InMemoryArtifactStore.new()
    {kept, removed} = Enum.split(context.retention_receipts, 7)
    owned = Backup.owned_receipts(context.backup_directory)

    Enum.map(owned, & &1["runId"]) == Enum.map(kept, & &1["runId"]) and
      Enum.all?(removed, fn receipt ->
        artifact = context.backup_directory <> "/" <> receipt["artifactBasename"]
        receipt_path = String.replace_suffix(artifact, ".sqlite3", ".receipt.json")

        not InMemoryArtifactStore.regular?(store, artifact) and
          not InMemoryArtifactStore.regular?(store, receipt_path)
      end)
  end

  def behaviour_outcome?(context, :preserve_unowned, _args) do
    store = InMemoryArtifactStore.new()

    match?(
      %{content: "synthetic-unowned"},
      InMemoryArtifactStore.file(store, context.unknown_backup_file)
    ) and
      match?(
        %{content: "retain"},
        InMemoryArtifactStore.file(store, context.previous_destination_file)
      )
  end

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
      context.page
      |> rendered_panels()
      |> Enum.map(&Map.take(&1, [:href, :label]))
      |> Kernel.==(Enum.map(context.declared_panels, &%{href: &1.path, label: &1.label}))

  # Each rendered panel names its declared owner and editable fields, and that owner, driven
  # through its facade, refuses or ignores every field outside them and keeps its stored
  # state; a panel whose owner has no proof here fails.
  def behaviour_outcome?(context, :owner_allowlists, _args) do
    panels = rendered_panels(context.page)

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

  def behaviour_outcome?(context, expected, args) when expected in @integrity_outcomes,
    do: BackupIntegrity.outcome?(context, expected, args)

  def behaviour_outcome?(context, expected, args) when expected in @label_outcomes,
    do: IntegrityLabel.outcome?(context, expected, args)

  def behaviour_outcome?(context, expected, args) when expected in @drill_outcomes,
    do: RestoreDrill.outcome?(context, expected, args)

  def behaviour_outcome?(context, expected, args),
    do: UnitFamilyChatDriver.behaviour_outcome?(context, expected, args)

  # A synthetic destination no disk holds: the scenario's in-memory artifact store keeps it.
  defp unit_backup_directory(tag),
    do:
      "/srv/test-user-backup/" <>
        tag <> "-" <> Integer.to_string(:erlang.unique_integer([:positive]))

  defp reconcile_task, do: Reconcile.execute([])

  defp enabled_button?(page, selector, label) do
    page
    |> LazyHTML.query("#{selector}:not([disabled])")
    |> Enum.any?(fn button -> button |> LazyHTML.text() |> String.contains?(label) end)
  end

  # Whether the page renders the control and none of its matches is disabled.
  defp enabled?(page, selector) do
    controls = LazyHTML.query(page, selector)
    not Enum.empty?(controls) and controls |> LazyHTML.attribute("disabled") |> Enum.empty?()
  end

  # Whether the page renders the control and every one of its matches is disabled.
  defp disabled?(page, selector) do
    controls = LazyHTML.query(page, selector)

    not Enum.empty?(controls) and
      length(LazyHTML.attribute(controls, "disabled")) == Enum.count(controls)
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

  # Installs the Storage facade's in-memory ports for the rest of the test, once.
  defp install_storage_ports! do
    if is_nil(GenServer.whereis(StoragePorts)) do
      previous = StoragePorts.install()
      ExUnit.Callbacks.on_exit(fn -> StoragePorts.restore(previous) end)
    end

    :ok
  end

  defp render_storage_page(socket) do
    socket.assigns
    |> Map.delete(:__changed__)
    |> StorageLive.render()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> LazyHTML.from_fragment()
  end

  # The database path the storage profile this layer runs under resolves to, worked out
  # here from the profile rather than through the Storage facade.
  defp profile_database_path do
    {:test, run_id} = Application.fetch_env!(:bnest_app, :storage_profile)
    StorageLocation.test_data_directory(run_id) <> "/bnest.sqlite3"
  end

  defp theme_owner(path), do: path |> String.split("/") |> Enum.at(1)

  # Pretty-printed, as a hand-edited flat file may be, so a source's bytes and its record's
  # canonical form have different digests.
  defp sqlite_storage_fixture_files,
    do:
      Enum.map(sqlite_storage_fixture_entries(), fn {path, record} ->
        {path, Jason.encode!(record, pretty: true)}
      end)

  # The flat store's records as the flat files a legacy installation keeps them in.
  defp flat_source_files(store),
    do:
      for(
        {{type, identity}, record} <- InMemoryRecordBackend.snapshot(store),
        do: {flat_source_path(type, identity), Jason.encode!(record)}
      )

  defp flat_source_path(:bootstrap, nil), do: "system/bootstrap.json"
  defp flat_source_path(:schema_registry, nil), do: "system/schema-registry.json"
  defp flat_source_path(:account, id), do: "system/accounts/#{id}.json"
  defp flat_source_path(:username_index, username), do: "system/usernames/#{username}.json"
  defp flat_source_path(:session, digest), do: "system/sessions/#{digest}.json"
  defp flat_source_path(:manifest, id), do: "system/manifests/#{id}.json"
  defp flat_source_path(:browser_import, {owner, id}), do: "users/#{owner}/imports/#{id}.json"
  defp flat_source_path(:chat, owner), do: "users/#{owner}/chat/current.json"
  defp flat_source_path(:sifat_allah, owner), do: "users/#{owner}/sifat-allah/progress.json"
  defp flat_source_path(:theme, owner), do: "users/#{owner}/preferences/theme.json"

  defp sqlite_storage_fixture_entries do
    [
      {"users/user-test-z-fixture/preferences/theme.json",
       sqlite_storage_theme_fixture("user-test-z-fixture", "light")},
      {"users/user-test-a-fixture/preferences/theme.json",
       sqlite_storage_theme_fixture("user-test-a-fixture", "dark")}
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

  # A real account on the browser request path whose browser reports `sources`; Storage's
  # import reaches the record repository over the request path's flat store.
  defp central_request_context(context, sources) do
    username = "test-user-unit-central"
    context = start_request_path(context, [synthetic_account(username, ["admin"])])

    Map.merge(context, %{
      central_store: context.request_store,
      central_owner: stored_account(context.request_store, username)["userId"],
      browser_sources: sources
    })
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
  # A response's redirect, followed as a browser does: to its location, carrying every cookie
  # the response set, so a session value or flash it wrote reaches the next page.
  defp follow_redirect(response, token) do
    [location] = Plug.Conn.get_resp_header(response, "location")
    dispatch_request(:get, location, token, %{}, response)
  end

  defp dispatch_request(method, path, token, params \\ %{}, previous \\ nil) do
    if is_nil(GenServer.whereis(BnestAppWeb.Endpoint)),
      do: ExUnit.Callbacks.start_supervised!(BnestAppWeb.Endpoint)

    Plug.CSRFProtection.delete_csrf_token()
    csrf_token = Plug.CSRFProtection.get_csrf_token()

    method
    |> Plug.Test.conn(path, params)
    |> recycle_cookies(previous)
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

  defp recycle_cookies(conn, nil), do: conn
  defp recycle_cookies(conn, previous), do: Plug.Test.recycle_cookies(conn, previous)

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

  # A controller's redirect to the login page (not halted by a pipeline guard).
  defp redirects_to_login?(%{status: 302} = response),
    do: match?(["/login" <> _rest], Plug.Conn.get_resp_header(response, "location"))

  defp redirects_to_login?(_response), do: false

  # Home's protected actions, read from the rendered page: the chat entry and logout form.
  defp protected_home?(%{status: 200, resp_body: body}) do
    page = LazyHTML.from_document(body)

    Enum.all?(["[data-role=chat-entry]", "form[action='/logout']"], fn selector ->
      page |> LazyHTML.query(selector) |> Enum.any?()
    end)
  end

  defp protected_home?(_response), do: false

  defp identity_cookie(response) do
    case response.resp_cookies["_bnest_identity"] do
      %{value: token} -> token
      nil -> nil
    end
  end

  # Store inspection outside the recorder: the snapshot is read without a record access.
  defp stored_account(store, username) do
    records = InMemoryRecordBackend.snapshot(store)
    %{"userId" => user_id} = Map.fetch!(records, {:username_index, username})
    Map.fetch!(records, {:account, user_id})
  end

  defp stored_verifier(store, username),
    do: stored_account(store, username)["passwordVerifier"]

  defp owner_access?({_operation, _type, owner}, owner), do: true
  defp owner_access?({_operation, _type, {owner, _key}}, owner), do: true
  defp owner_access?(_access, _owner), do: false

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

  # Home as an administrator sees it, then the page its `role` entry links to: the production
  # `mount/3` of the LiveView the router serves there, on a connected socket, rendered with
  # its template.
  defp follow_admin_entry(role) do
    [href] =
      %{}
      |> render_home(@unit_admin)
      |> Map.fetch!(:page)
      |> LazyHTML.query("[data-role=#{role}]")
      |> LazyHTML.attribute("href")

    view = routed_live_view(href)

    socket = %Socket{
      view: view,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}, current_user: @unit_admin}
    }

    {:ok, socket} = view.mount(%{}, %{}, socket)

    socket.assigns
    |> Map.delete(:__changed__)
    |> view.render()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> LazyHTML.from_fragment()
  end

  defp schedule_row(page, group_title_id, schedule_key),
    do:
      LazyHTML.query(
        page,
        ~s(section[aria-labelledby="#{group_title_id}"] .schedule-row[data-schedule-key="#{schedule_key}"])
      )

  defp rendered_panels(page) do
    page
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
  # another, and the pointer store sees no write.
  defp owner_saves_only_allowlisted?(_context, %{owner: "BnestApp.Storage", fields: ""}) do
    path = Storage.database_path()
    refused = Storage.persist_directory("/srv/test-user-storage/elsewhere")

    refused == {:error, :immutable} and Storage.database_path() == path and
      not Enum.any?(StoragePorts.calls(), &match?({:write_config, _config}, &1))
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
      destination == {:error, :not_absolute} and
      InMemoryBackupConfigStore.writes(InMemoryBackupConfigStore.new()) == []
  end

  defp owner_saves_only_allowlisted?(_context, _panel_without_proof), do: false

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

  # The administrator's schedules page, mounted connected: the check it starts reports to this
  # process, and `IntegrityLabel.settle/1` hands that report to the socket, as the LiveView
  # channel would. The backup schedule row is the Scheduler's singleton, put as the release
  # seeds put it.
  defp mount_schedules_page do
    :ok = put_schedule!("prod-sqlite-backup-daily", "prod_sqlite_backup", "admin_system")

    if is_nil(GenServer.whereis(BnestApp.Scheduler.Tasks)),
      do: ExUnit.Callbacks.start_supervised!({Task.Supervisor, name: BnestApp.Scheduler.Tasks})

    socket = %Socket{
      view: AdminScheduleSettingsLive,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}, current_user: @unit_admin}
    }

    {:ok, socket} = AdminScheduleSettingsLive.mount(%{}, %{}, socket)
    socket
  end

  defp open_label_page(context) do
    socket = mount_schedules_page()
    first = render_schedules_page(socket)
    settled = IntegrityLabel.settle(socket)

    Map.merge(context, %{
      schedules_socket: settled,
      label_first: first,
      label_page: render_schedules_page(settled)
    })
  end

  defp note_viewport(context, [width, height]), do: Map.put(context, :viewport, {width, height})
  defp note_viewport(context, []), do: context

  # A form's submission as the browser sends it: every field as the page rendered it.
  defp label_form(page, "daily") do
    value = fn selector ->
      [value] = page |> LazyHTML.query(selector) |> LazyHTML.attribute("value")
      value
    end

    schedule = %{
      "revision" => value.("input[name='schedule[revision]']"),
      "daily_time_wib" => value.("input[name='schedule[daily_time_wib]']")
    }

    enabled? =
      page |> LazyHTML.query("input[name='schedule[enabled]']") |> LazyHTML.attribute("checked") !=
        []

    {"save_schedule",
     %{"schedule" => if(enabled?, do: Map.put(schedule, "enabled", "true"), else: schedule)}}
  end

  defp label_form(page, "backup_folder") do
    [directory] =
      page
      |> LazyHTML.query("input[name='backup[destination_directory]']")
      |> LazyHTML.attribute("value")

    {"save_backup", %{"backup" => %{"destination_directory" => directory}}}
  end

  defp render_schedules_page(socket) do
    socket.assigns
    |> Map.delete(:__changed__)
    |> AdminScheduleSettingsLive.render()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> LazyHTML.from_fragment()
  end

  # Waits, for up to five seconds, until the Scheduler's task supervisor runs no task.
  defp await_scheduler_tasks(attempts \\ 500)

  defp await_scheduler_tasks(0), do: raise("a queued scheduler task did not finish")

  defp await_scheduler_tasks(attempts) do
    if Task.Supervisor.children(BnestApp.Scheduler.Tasks) != [] do
      receive do
      after
        10 -> await_scheduler_tasks(attempts - 1)
      end
    end

    :ok
  end

  # A transient failure of a claimed attempt, recorded in the Scheduler's configured store
  # the way its run records one.
  defp fail_attempt(run_id, attempt, now),
    do: ScheduleStore.fail_attempt(Scheduler.store(), run_id, attempt, :capacity, now)
end
