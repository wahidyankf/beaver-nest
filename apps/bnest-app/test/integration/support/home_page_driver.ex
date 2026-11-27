defmodule BnestApp.Behaviour.IntegrationHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver
  @endpoint BnestAppWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import BnestApp.Test.BehaviourEvidence

  alias BnestApp.Backup
  alias BnestApp.Backup.Adapters.ScheduledBackupTask
  alias BnestApp.Backup.Domain.Receipt
  alias BnestApp.Behaviour.IntegrationFamilyChatDriver
  alias BnestApp.Behaviour.TestIsolation.IntegrationAdapter
  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.{Conversations, Transcript}
  alias BnestApp.CodexChat.Domain.RunnerEvent
  alias BnestApp.CodexChat.ModelCatalog
  alias BnestApp.Identity.Adapters.{Argon2CredentialHasher, RecordIdentityStore}
  alias BnestApp.Identity.Bootstrap
  alias BnestApp.Identity.Domain.Authorization
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
  alias BnestApp.Storage.Adapters.SqliteRelocation
  alias BnestApp.Storage.Domain.FlatMigration
  alias BnestApp.Storage.Domain.Location, as: StorageLocation
  alias BnestApp.Storage.Domain.Normalizer
  alias BnestApp.Storage.Import
  alias BnestApp.Storage.Migration, as: StorageMigration
  alias BnestApp.Storage.Ports.RecordBackend
  alias BnestApp.Storage.Records
  alias BnestApp.Test.BackupIntegrity
  alias BnestApp.Test.CodexFixtureConversation
  alias BnestApp.Test.CodexFixtureModels, as: FixtureModels
  alias BnestApp.Test.CodexReplyPage
  alias BnestApp.Test.InMemory.FailingTranscriptStore, as: InMemoryFailingTranscriptStore
  alias BnestApp.Test.InMemory.GeneratedImages, as: InMemoryGeneratedImages
  alias BnestApp.Test.IntegrityLabel
  alias BnestApp.Test.InterruptedChatWriteBackend
  alias BnestApp.Test.InterruptedMigrationLedger
  alias BnestApp.Test.ObservedArtifactStore
  alias BnestApp.Test.RestoreDrill
  alias BnestApp.Test.SchedulerDispatch
  alias BnestApp.Test.Seeds.Schedules
  alias BnestApp.TestBackupDestination
  alias BnestApp.TestRuntimeRoot
  alias BnestAppWeb.ChatComponents
  alias BnestAppWeb.ChatMarkdown
  alias BnestAppWeb.Pwa
  alias Mix.Tasks.Bnest.Backup.Reconcile
  alias Phoenix.HTML.Safe

  @behaviour_now ~U[2026-08-30 20:00:00Z]
  # The repository checkout, the Codex working directory the production configuration names.
  @repository_checkout Path.expand("../../../../..", __DIR__)
  @synthetic_image <<0x89, "PNG\r\n", 0x1A, "\n">> <> "synthetic"
  @schedules_route "/admin/settings/schedules"
  @record_operations [:read, :write, :put_new, :replace, :remove_exact]
  @quiz_auto_advance_ms 5_000

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

  # BN-DATA-01: the routed migration page fed the browser sources the scenario
  # holds, as its hook would report them.
  def open(%{conn: conn} = context, "/data-migration") do
    {:ok, view, _html} = live(conn, "/data-migration")
    render_hook(view, "browser-sources", %{"sources" => Map.get(context, :browser_sources, [])})
    html = render(view)

    context
    |> Map.put(:view, view)
    |> Map.put(:route, "/data-migration")
    |> Map.put(:migration_html, LazyHTML.from_fragment(html))
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

  # Installability is what a visitor's document declares after opening "/": the root
  # layout's manifest and icon links, each served by the endpoint. The manifest's contents
  # and service-worker activation are proven at E2E.
  @impl true
  def installable_as_app?(context) do
    document = context.page
    manifest = document |> LazyHTML.query("link[rel=manifest]") |> LazyHTML.attribute("href")

    icons =
      document
      |> LazyHTML.query("link[rel=icon][type='image/png'], link[rel=apple-touch-icon]")
      |> LazyHTML.attribute("href")

    manifest == ["/manifest.webmanifest"] and "/images/beaver-nest-512.png" in icons and
      Enum.all?(manifest ++ icons, &served_path?(context, &1))
  end

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

  # The landmark structure that keeps controls and content separated: the header holds
  # the brand and account controls, and the hero section stands beside it. Pixel overlap is
  # measured in the browser.
  @impl true
  def home_controls_arranged?(context) do
    page = context.page

    not Enum.empty?(LazyHTML.query(page, ".home-header > .home-brand")) and
      not Enum.empty?(LazyHTML.query(page, ".home-header > .home-account")) and
      not Enum.empty?(LazyHTML.query(page, ".home-hero"))
  end

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
  def model_selector_lists_only?(context, names) do
    context.view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-role=model-selector] option")
    |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))
    |> Kernel.==(names)
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
    # A busy turn makes the box read-only; a model that is not available disables it. Either lock counts.
    has_element?(
      context.view,
      "#chat-composer-form textarea[data-role=chat-composer][readonly], #chat-composer-form textarea[data-role=chat-composer][disabled]"
    ) and
      not has_element?(
        context.view,
        "#chat-composer-form textarea:not([readonly]):not([disabled])"
      ) and
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

    not Enum.empty?(actions) and
      has_element?(context.view, ".chat-controls > .model-badge") and
      has_element?(context.view, ".chat-actions > .clear-chat[data-role=clear-chat-group]") and
      has_element?(context.view, ".chat-controls > .chat-access[data-role=repository-access]")
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
  # Shift+Enter sends only from a touch pointer (ADR 005, decision 1). The pointer is a browser state, so this
  # proof checks the scenario's declared pointer and runs its send; the key chord itself is proven by browser tests.
  def submit_with_shift_enter(%{visitor_pointer: :touch} = context, message),
    do: send_message(context, message)

  def submit_with_shift_enter(_context, _message),
    do:
      raise(
        "Shift+Enter sends only from a touch pointer, and this scenario declares no touch pointer"
      )

  # The composer is read-only while Codex works, so the rendered form is submitted as a forced
  # browser submission would; the LiveView's own busy guard decides what happens.
  @impl true
  def attempt_message_before_finished(context, message) do
    unless composer_unavailable?(context), do: raise("the chat composer is not locked")

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

  # A dropped socket remounts the route on the same server: only what the LiveView saved
  # comes back, and a turn still owed is resent through the resumed session. The stale view
  # is stopped first, so its checkpoint cannot save over the resumed chat.
  @impl true
  def reconnect(context) do
    draft =
      context.view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#chat-composer-form textarea")
      |> LazyHTML.text()

    held = Map.fetch(context, :pending_codex_events)
    :ok = GenServer.stop(context.view.pid)

    {:ok, view, _html} = live(context.conn, "/chat")
    remounted = Map.put(context, :view, view)

    remounted =
      if held == :error,
        do: remounted,
        else: Map.put(remounted, :pending_codex_events, elem(held, 1))

    calls = codex_fixture_calls()
    remounted = Map.update(remounted, :codex_calls, calls, &(&1 ++ calls))

    remounted =
      if Enum.any?(calls, &match?({:prompt, owner, _} when owner == view.pid, &1)) do
        resume_answer(remounted, held)
      else
        remounted
      end

    if draft == "", do: remounted, else: type_draft(remounted, draft)
  end

  # The resumed turn's answer, played as the fixture Codex sends it: a held stream's
  # replacement streams its first part and holds the rest for the scenario's next step.
  defp resume_answer(context, :error) do
    {events, context} = answer_current_prompt(context)
    deliver_codex_events(context, events) |> persist_chat()
  end

  defp resume_answer(context, {:ok, _held}) do
    {events, context} = answer_current_prompt(context)
    {first, rest} = CodexFixtureConversation.split_first_part(events)

    context
    |> Map.put(:pending_codex_events, rest)
    |> deliver_codex_events(first)
    |> persist_chat()
  end

  defp answer_current_prompt(context) do
    {prompt, session, context} = unanswered_prompt!(context)

    {events, threads} =
      CodexFixtureConversation.answer(Map.get(context, :codex_threads, %{}), session, prompt)

    {events, Map.put(context, :codex_threads, threads)}
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
    # LiveViewTest runs no client script, so the confirmation (chat_controls.js) is not opened here. "Yes, delete" is
    # the only control that sends the clear; the browser suite covers the confirmation step itself.
    context.view
    |> element("[data-role=clear-chat-yes]")
    |> render_click()

    %{} = await_push_event(context.view, "clear-chat-storage")
    Map.delete(context, :persisted_chat)
  end

  @impl true
  def start_new_chat(context) do
    unless has_element?(context.view, "[data-role=new-conversation]"),
      do: raise("the chat page offers no new-chat control")

    context.view |> element("[data-role=new-conversation]") |> render_click()

    unless conversation_list_shows?(context, "New chat") and conversation_empty?(context),
      do: raise("starting a new chat did not open an empty conversation")

    context
  end

  @impl true
  def conversation_list_shows?(context, title) do
    has_element?(context.view, "[data-role=select-conversation]", title)
  end

  # Opening a conversation follows its rail entry, as the patch link does: the
  # conversation's own session reconnects and its messages come back.
  @impl true
  def open_conversation(context, title) do
    id = conversation_id!(context, title)
    render_patch(context.view, "/chat?conversation=#{id}")

    unless conversation_selected?(context, title),
      do: raise("opening the conversation did not select it")

    context
  end

  @impl true
  def delete_conversation(context, title) do
    id = conversation_id!(context, title)

    context.view
    |> element("[data-role=delete-conversation][phx-value-id=\"#{id}\"]")
    |> render_click()

    if conversation_list_shows?(context, title),
      do: raise("deleting the conversation did not remove it from the rail")

    context
  end

  @impl true
  def rename_conversation(context, title, next) do
    id = conversation_id!(context, title)

    context.view
    |> element("[data-role=rename-toggle][phx-value-id=\"#{id}\"]")
    |> render_click()

    context.view
    |> element("form[phx-submit=rename_conversation]")
    |> render_submit(%{"conversation_id" => id, "title" => next})

    unless conversation_list_shows?(context, next),
      do: raise("renaming the conversation did not retitle it on the rail")

    context
  end

  # The drawer opens and closes in the browser (conversation_drawer.js); the integration layer proves the rendered
  # contract that script depends on: the toggle naming the drawer, the rail, the scrim and the close control.
  @impl true
  def assert_conversation_drawer_rendered(context) do
    unless conversation_drawer_rendered?(context),
      do: raise("the chat page offers no conversation drawer")

    context
  end

  @impl true
  def conversation_drawer_contract_rendered?(context), do: conversation_drawer_rendered?(context)

  @impl true
  def assert_conversation_drawer_closable(context) do
    unless conversation_drawer_rendered?(context),
      do: raise("the chat page offers no conversation drawer")

    context
  end

  # The server renders the drawer closed; closing returns it there. The overlay close itself is browser-proven.
  @impl true
  def conversation_drawer_rendered_closed?(context) do
    context.view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-role=conversations-toggle]")
    |> LazyHTML.attribute("aria-expanded") == ["false"]
  end

  # No layout engine runs here; the class names the stylesheet rule that sizes the toggle to 44 pixels.
  @impl true
  def chats_toggle_sized_by_stylesheet?(context) do
    has_element?(context.view, "[data-role=conversations-toggle].conversations-toggle")
  end

  # Scrolling is a browser act on the rendered conversation; the scroll target the step acts on must exist for it.
  @impl true
  def assert_scroll_target_rendered(context) do
    unless has_element?(context.view, "#chat-conversation"),
      do: raise("the chat page renders no conversation to scroll")

    context
  end

  # The message and composer boxes are browser layout results; the regions the browser measures are rendered.
  @impl true
  def conversation_and_composer_rendered?(context) do
    has_element?(context.view, "#chat-conversation") and
      has_element?(context.view, "#chat-composer-form")
  end

  @impl true
  def composer_form_rendered?(context) do
    has_element?(context.view, "#chat-composer-form")
  end

  @impl true
  def chat_shell_rendered?(context) do
    has_element?(context.view, ".chat-shell")
  end

  defp conversation_drawer_rendered?(context) do
    rendered = context.view |> render() |> LazyHTML.from_fragment()

    [
      "[data-role=conversations-toggle][aria-controls=conversation-drawer]",
      "#conversation-drawer[data-role=conversation-rail]",
      "[data-role=conversation-scrim]",
      "[data-role=conversation-close]"
    ]
    |> Enum.all?(fn selector -> not Enum.empty?(LazyHTML.query(rendered, selector)) end)
  end

  defp conversation_selected?(context, title) do
    context.view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(
      "[data-role=conversation-item][aria-current=true] [data-role=select-conversation]"
    )
    |> Enum.any?(fn element -> element |> LazyHTML.text() |> String.trim() == title end)
  end

  defp conversation_id!(context, title) do
    context.view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-role=conversation-item]")
    |> Enum.find_value(fn item ->
      if item
         |> LazyHTML.query("[data-role=select-conversation]")
         |> LazyHTML.text()
         |> String.trim() == title,
         do: item |> LazyHTML.attribute("data-conversation-id") |> List.first()
    end) || raise("the chat rail offers no conversation #{inspect(title)}")
  end

  # The fixture Codex's reply comes in two parts, as the unit layer delivers it: the page is read
  # after the first part, then after the rest. Each part is persisted before the page is read.
  @impl true
  def stream_first_codex_part(context) do
    {prompt, session, context} = unanswered_prompt!(context)

    {events, threads} =
      CodexFixtureConversation.answer(Map.get(context, :codex_threads, %{}), session, prompt)

    {first, rest} = CodexFixtureConversation.split_first_part(events)

    context
    |> Map.put(:codex_threads, threads)
    |> Map.put(:pending_codex_events, rest)
    |> deliver_codex_events(first)
    |> persist_chat()
  end

  @impl true
  def stream_rest_of_codex_reply(context) do
    rest = Map.fetch!(context, :pending_codex_events)

    context
    |> Map.delete(:pending_codex_events)
    |> deliver_codex_events(rest)
    |> persist_chat()
  end

  defp persist_chat(context) do
    snapshot = await_push_event(context.view, "persist-chat")
    Map.put(context, :persisted_chat, Jason.encode!(snapshot))
  end

  defp chat_page(context), do: context.view |> render() |> LazyHTML.from_fragment()

  defp latest_reply(context), do: context |> chat_page() |> CodexReplyPage.latest_reply()

  # A finished reply is `phx-update="ignore"`, so the test client's `render()` keeps the
  # reply's last streaming HTML: the completion patch updates only its `data-*` attributes.
  # The test client decides from the element the server sends, while a browser decides from
  # the element on the page and applies the completion patch, so the diagram marker and the
  # refusal notes arrive there (ADR 004, Decision 3; drawing itself is proven by the browser
  # suite). The completion is observable — `data-streaming` flips to `"false"` — and the
  # server persists the finished content, so the HTML below is what the finished reply carries
  # in a browser: the shared component's own bytes for the persisted content.
  defp completed_reply_shows_text?(context, text) do
    case completed_reply(context) do
      nil -> false
      reply -> CodexReplyPage.shows_text?(reply, text)
    end
  end

  defp completed_reply_plain_code_blocks(context) do
    case completed_reply(context) do
      nil -> nil
      reply -> CodexReplyPage.plain_diagram_count(reply)
    end
  end

  defp completed_reply_marked_diagrams(context) do
    case completed_reply(context) do
      nil -> nil
      reply -> CodexReplyPage.marked_diagram_count(reply)
    end
  end

  # The finished reply the server holds, rendered the way the page carries it: `nil` while
  # the reply still streams or its persisted content is unavailable.
  defp completed_reply(context) do
    with true <- context |> latest_reply() |> CodexReplyPage.complete?(),
         {:ok, content, update_count} <- completed_reply_source(context) do
      html =
        ChatComponents.markdown_body_html(content,
          streaming: false,
          codex_images: true,
          attrs: %{
            "data-role" => "assistant-message",
            "data-streaming" => "false",
            "data-update-count" => to_string(update_count)
          }
        )

      CodexReplyPage.latest_reply(LazyHTML.from_fragment(html))
    else
      _ -> nil
    end
  end

  # The latest assistant message the server persisted for this scenario's conversation.
  defp completed_reply_source(context) do
    with persisted when is_binary(persisted) <- Map.get(context, :persisted_chat),
         {:ok, %{"conversations" => conversations, "selected_id" => selected_id}} <-
           Jason.decode(persisted),
         %{"transcript" => %{"messages" => messages}} <- Map.get(conversations, selected_id),
         %{"content" => content, "update_count" => update_count} <-
           messages |> Enum.filter(&(&1["role"] == "assistant")) |> List.last() do
      {:ok, content, update_count}
    else
      _ -> :error
    end
  end

  @impl true
  def latest_codex_reply_streaming?(context),
    do: CodexReplyPage.streaming?(latest_reply(context))

  @impl true
  def latest_codex_reply_complete?(context), do: CodexReplyPage.complete?(latest_reply(context))

  @impl true
  def latest_codex_reply_contains_element?(context, element),
    do: CodexReplyPage.contains_element?(latest_reply(context), element)

  @impl true
  def latest_codex_reply_contains_element_with_text?(context, element, text),
    do: CodexReplyPage.contains_element_with_text?(latest_reply(context), element, text)

  @impl true
  def latest_codex_reply_lacks_element?(context, element),
    do: not latest_codex_reply_contains_element?(context, element)

  @impl true
  def latest_codex_reply_shows_text?(context, text) do
    CodexReplyPage.shows_text?(latest_reply(context), text) or
      completed_reply_shows_text?(context, text)
  end

  @impl true
  def latest_codex_reply_shows_text_without_link?(context, text),
    do: CodexReplyPage.shows_text_without_link?(latest_reply(context), text)

  @impl true
  def latest_codex_reply_lacks_text?(context, text),
    do: not latest_codex_reply_shows_text?(context, text)

  @impl true
  def latest_codex_reply_lacks_link_to_address?(context, prefix),
    do: CodexReplyPage.lacks_link_to_address?(latest_reply(context), prefix)

  @impl true
  def latest_codex_reply_links_to?(context, label, address),
    do: CodexReplyPage.links_to?(latest_reply(context), label, address)

  @impl true
  def link_opens_in_new_tab_privately?(context, label),
    do: CodexReplyPage.opens_in_new_tab_privately?(latest_reply(context), label)

  @impl true
  def latest_codex_reply_task_checkboxes?(context, checked, unchecked),
    do: CodexReplyPage.task_checkboxes?(latest_reply(context), checked, unchecked)

  @impl true
  # The structure the browser layout check measures: table, task list, link and image
  # inside the reply bubble. Visual layout itself is proven in the browser.
  def latest_codex_reply_lays_out_inside_bubble?(context),
    do: CodexReplyPage.lays_out_structure?(latest_reply(context))

  @impl true
  def latest_codex_reply_holds_wide_content?(context),
    do: CodexReplyPage.holds_wide_content?(latest_reply(context))

  @impl true
  def latest_codex_reply_shows_inline_image?(context, alt),
    do: CodexReplyPage.shows_inline_image?(latest_reply(context), alt)

  @impl true
  def latest_codex_reply_loads_inline_image?(context, alt, address),
    do: CodexReplyPage.loads_inline_image?(latest_reply(context), alt, address)

  @impl true
  def latest_codex_reply_keeps_plain_code_blocks?(context, count) do
    if CodexReplyPage.plain_diagram_count(latest_reply(context)) == count do
      true
    else
      completed_reply_plain_code_blocks(context) == count
    end
  end

  @impl true
  def latest_codex_reply_marks_diagrams?(context, count) do
    if CodexReplyPage.marked_diagram_count(latest_reply(context)) == count do
      true
    else
      completed_reply_marked_diagrams(context) == count
    end
  end

  @impl true
  def latest_codex_reply_shows_repository_image?(context, path),
    do: CodexReplyPage.shows_repository_image?(latest_reply(context), path)

  # One HTTP request through the endpoint, as the visitor's browser makes it: the signed-in
  # visitor's connection carries the session, the signed-out visitor's carries none.
  @impl true
  def request_repository_image(context, path) do
    route = "/chat/images/" <> URI.encode(path, &URI.char_unreserved?/1)
    Map.merge(context, %{image_response: get(context.conn, route), image_request_path: route})
  end

  @impl true
  def image_response_status?(context, status), do: context.image_response.status == status

  @impl true
  def image_response_content_type?(context, type) do
    context.image_response
    |> Plug.Conn.get_resp_header("content-type")
    |> Enum.map(&(&1 |> String.split(";") |> hd() |> String.trim()))
    |> Kernel.==([type])
  end

  @impl true
  def image_response_empty_not_found?(context) do
    context.image_response.status == 404 and context.image_response.resp_body == ""
  end

  @impl true
  def image_response_redirects_to?(context, prefix) do
    context.image_response.status == 302 and
      context.image_response
      |> Plug.Conn.get_resp_header("location")
      |> Enum.any?(&String.starts_with?(&1, prefix))
  end

  # The scenario's repository is a runtime root of its own, which the adapter reads as the Codex
  # working directory (the configured `:codex` working directory is restored afterwards). A
  # scenario that puts no file in it reads the checkout, which is the production configuration.
  @impl true
  def repository_holds_file(context, path, content) do
    {root, context} = ensure_repository_root(context)
    full = Path.join(root.path, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content)
    context
  end

  @impl true
  def repository_holds_symbolic_link(context, link, target) do
    {root, context} = ensure_repository_root(context)
    full = Path.join(root.path, link)
    File.mkdir_p!(Path.dirname(full))
    File.ln_s!(Path.join(@repository_checkout, target), full)
    context
  end

  @impl true
  def repository_holds_sized_file(context, path, bytes) do
    {root, context} = ensure_repository_root(context)
    full = Path.join(root.path, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, <<0x89, "PNG\r\n", 0x1A, "\n">> <> :binary.copy(<<0>>, bytes - 8))
    context
  end

  # A decoy the request must refuse. The file lands where the path points, and only inside the
  # scenario's run root: a path that climbs out of the repository still ends in the run root, and
  # any path that would end outside it fails the scenario before anything is written.
  @impl true
  def repository_holds_image(context, path) do
    {root, context} = ensure_repository_root(context)
    full = Path.expand(Path.join(root.path, path))

    unless String.starts_with?(full, root.run <> "/"),
      do: raise("the scenario may not write #{inspect(path)} outside its run root")

    File.mkdir_p!(Path.dirname(full))
    File.write!(full, @synthetic_image)
    context
  end

  # The repository is the `repo` folder of the scenario's own run root, which the adapter reads as
  # the Codex working directory. Keeping it one level down leaves room for a path that climbs out
  # of the repository and still lands in the run root, where the test owns every file.
  defp ensure_repository_root(%{repository_root: root} = context), do: {root, context}

  defp ensure_repository_root(context) do
    runtime = TestRuntimeRoot.create!("codex-images")
    ExUnit.Callbacks.on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)

    repository = %{path: Path.join(runtime.path, "repo"), run: runtime.path}
    File.mkdir_p!(repository.path)

    codex = Application.fetch_env!(:bnest_app, :codex)

    Application.put_env(
      :bnest_app,
      :codex,
      Keyword.put(codex, :working_directory, repository.path)
    )

    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:bnest_app, :codex, codex) end)

    {repository, Map.put(context, :repository_root, repository)}
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
    if role == :admin and String.ends_with?(context.feature_file, "test_instances.feature") do
      # This feature's admin lives in a test instance that the isolation adapter spawns and logs in to.
      IntegrationAdapter.establish_admin(context)
    else
      scenario_identity(context, role)
    end
  end

  # A scenario's identity in the shared run database, logged in as a browser's login would.
  defp scenario_identity(context, role) do
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

  # The identity cutover flag is read per request, so a scenario pins it and
  # restores the configured value afterwards.
  def prepare_behaviour(context, :cutover_off, _args),
    do: pin_cutover(context, false)

  def prepare_behaviour(context, :cutover_on, _args),
    do: pin_cutover(context, true)

  # The scenario's own synthetic account, hashed by the real Argon2id hasher when ConnCase
  # seeded it.
  def prepare_behaviour(context, state, _args)
      when state in [:approved_account, :approved_argon2_account] do
    identity = context.test_identity
    store = BnestApp.Identity.adapter(:identity_store).new(Storage.active_store())
    {:ok, account} = IdentityStore.read_account(store, identity.user_id)

    Map.merge(context, %{
      account_exists: true,
      identity_username: identity.username,
      identity_password: identity.password,
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

  # Two seeded synthetic accounts, each owning a stored theme preference.
  def prepare_behaviour(context, :two_isolated_users, _args) do
    key = "#{inspect(context.module)}:#{context.test}"

    {_conn, first} =
      BnestAppWeb.ConnCase.scenario_authenticated_conn(build_conn(), key <> ":first")

    {_conn, second} =
      BnestAppWeb.ConnCase.scenario_authenticated_conn(build_conn(), key <> ":second", ["parents"])

    {:ok, token} = BnestApp.Identity.login(first.username, first.password)
    {:ok, first_user} = BnestApp.Identity.current_user(token)
    :ok = Preferences.put_theme(first.user_id, "light", DateTime.utc_now())
    :ok = Preferences.put_theme(second.user_id, "dark", DateTime.utc_now())

    Map.merge(context, %{
      first_user: first_user,
      second_owner: second.user_id,
      second_theme_before: Preferences.theme(second.user_id)
    })
  end

  # Each Given only fills the browser's storage report; the import page decides what to do
  # with every source when the user confirms.
  def prepare_behaviour(context, :recognized_browser_sources, _args),
    do:
      Map.merge(context, %{
        central_store: Records.store(),
        browser_sources: Enum.map(recognized_browser_sources(), &Map.put(&1, "present", true))
      })

  def prepare_behaviour(context, :absent_theme_source, _args),
    do:
      Map.merge(context, %{
        central_store: Records.store(),
        browser_sources: [
          %{"storageArea" => "localStorage", "storageKey" => "phx:theme", "present" => false}
        ]
      })

  # The server already holds an accepted chat record; the browser's chat key now holds
  # malformed data.
  def prepare_behaviour(context, :invalid_browser_source, _args) do
    store = Records.store()
    {:ok, _accepted} = Import.browser(store, context.user_id, chat_source())
    malformed = %{chat_source() | "payload" => "{malformed"}

    Map.merge(context, %{
      central_store: store,
      accepted_before: FileRecordBackend.read(store, :chat, context.user_id),
      browser_sources: [Map.put(malformed, "present", true)]
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

  # BN-DATA-01: chat and learning data present, no explicit theme, and one foreign
  # key the page must ignore.
  def prepare_behaviour(context, :migration_mixed_sources, _args) do
    Map.put(context, :browser_sources, [
      Map.put(chat_source(), "present", true),
      Map.put(learning_source(), "present", true),
      %{"storageArea" => "localStorage", "storageKey" => "phx:theme", "present" => false},
      %{
        "storageArea" => "localStorage",
        "storageKey" => "unknown.key",
        "present" => true,
        "payload" => "keep"
      }
    ])
  end

  # BN-DATA-09: one chat source filed per outcome row of the outline.
  def prepare_behaviour(context, :filed_browser_source, ["accepted"]) do
    Map.put(context, :browser_sources, [Map.put(chat_source(), "present", true)])
  end

  def prepare_behaviour(context, :filed_browser_source, ["rejected"]) do
    malformed = %{chat_source() | "payload" => "{malformed"}
    Map.put(context, :browser_sources, [Map.put(malformed, "present", true)])
  end

  # A retryable outcome needs a storage write failure the browser cannot cause on a
  # healthy server: the accepted manifest is corrupted first, so resuming the same
  # import fails to read back.
  def prepare_behaviour(context, :filed_browser_source, ["retryable"]) do
    store = Records.store()
    source = Map.put(chat_source(), "present", true)
    {:ok, %{import_id: import_id}} = Import.browser(store, context.user_id, source)

    import_id
    |> manifest_path(store)
    |> File.write!("{corrupted")

    Map.merge(context, %{central_store: store, browser_sources: [source]})
  end

  def prepare_behaviour(context, :filed_browser_source, ["stale"]) do
    store = Records.store()
    {:ok, _accepted} = Import.browser(store, context.user_id, chat_source())

    stale_payload =
      chat_source()["payload"] |> Jason.decode!() |> Map.put("model", "stale") |> Jason.encode!()

    Map.merge(context, %{
      central_store: store,
      browser_sources: [
        %{chat_source() | "payload" => stale_payload} |> Map.put("present", true)
      ]
    })
  end

  # The saved chat is the precondition, so it is saved through the CodexChat facade into the
  # run-root repository, on the thread the fixture agent session cannot resume.
  def prepare_behaviour(context, :unavailable_codex_thread, _args) do
    {:ok, transcript} =
      Transcript.new("gpt-6.1-terra", "medium") |> Transcript.submit("Remember this transcript")

    transcript =
      transcript
      |> Transcript.update_assistant("Saved response")
      |> Transcript.complete()
      |> Transcript.put_thread_id("unavailable-thread")

    {:ok, _record} = CodexChat.save_transcript(context.user_id, transcript, nil)
    Map.put(context, :transcript_before, transcript.messages)
  end

  def prepare_behaviour(context, :no_backup_override, _args), do: prepare_default_backup(context)

  # The administrator's routed schedules page, with the backup folder form it renders.
  def prepare_behaviour(context, :admin_opened_schedules, _args) do
    context = prepare_backup_destination(context)
    {:ok, view, _html} = live(context.conn, "/admin/settings/schedules")

    unless has_element?(view, "form[phx-submit=save_backup] input#backup-directory"),
      do: raise("the schedules page renders no backup folder form")

    Map.put(context, :schedules_view, view)
  end

  # BN-SIFAT-16: the learner studies with one remembered pair saved, then saves fail.
  def prepare_behaviour(context, :sifat_saved_studying, _args) do
    {:ok, view, _html} = live(context.conn, "/apps/sifat-allah")
    context = Map.put(context, :view, view)

    context = context |> start_learning() |> mark_current_pair_remembered()
    context.view |> element("button", "Pasangan berikutnya →") |> render_click()
    context
  end

  # BN-SIFAT-17: the revision page prepared for the account user and the local
  # browser user.
  def prepare_behaviour(context, :sifat_account_ready, _args),
    do: Map.put(context, :sifat_ready_user, :account)

  def prepare_behaviour(context, :sifat_browser_ready, _args) do
    previous = Application.fetch_env!(:bnest_app, :identity_cutover_enabled)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, :identity_cutover_enabled, previous)
    end)

    Application.put_env(:bnest_app, :identity_cutover_enabled, false)
    Map.put(context, :sifat_ready_user, :browser)
  end

  # BN-ADMIN-04 and BN-ADMIN-05: the routed schedules page over the saved daily
  # schedule (02:00 WIB), so a refused save keeps it. The singleton schedule is
  # seeded idempotently, then saved once; the page renders that revision.
  def prepare_behaviour(context, :schedules_saved_opened, _args) do
    ensure_scheduler_storage()
    key = "prod-sqlite-backup-daily"
    :ok = PersistentSchedules.apply_and_verify!(@behaviour_now)
    current = Scheduler.get_schedule(key)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, saved} =
      Scheduler.update_daily(
        key,
        %{
          "daily_time_wib" => "02:00",
          "enabled" => "true",
          "revision" => Integer.to_string(current.revision)
        },
        now
      )

    {:ok, view, _html} = live(context.conn, @schedules_route)
    Map.merge(context, %{schedule_key: key, saved_schedule: saved, schedules_view: view})
  end

  # BN-ADMIN-06: the routed schedules page with no save attempted yet.
  def prepare_behaviour(context, :schedules_opened, _args) do
    ensure_scheduler_storage()
    :ok = PersistentSchedules.apply_and_verify!(@behaviour_now)
    {:ok, view, _html} = live(context.conn, @schedules_route)
    Map.merge(context, %{schedule_key: "prod-sqlite-backup-daily", schedules_view: view})
  end

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
  def prepare_behaviour(context, :storage_ui_not_visited, _args),
    do: Map.put(context, :storage_ui_visits, watch_storage_ui_visits())

  def prepare_behaviour(%{view: view} = context, :migration_not_started, _args) do
    unless has_element?(view, "section[aria-label='Migration status']", "Not started") do
      raise "storage migration already started"
    end

    Map.put(context, :migration_not_started?, true)
  end

  # The scenario is a fresh installation with no storage choice yet (ADR 001, section 1). Activation writes a
  # flat-primary pointer into the instance, and the storage choice is refused while a pointer exists, so the
  # instance's own pointer is removed here. With no pointer the default database directory is the storage profile's,
  # so the profile points at a runtime root of its own: the run base's database is never opened.
  def prepare_behaviour(context, :admin_opened_storage_settings, _args) do
    remove_instance_pointer!()
    runtime = TestRuntimeRoot.create!("sqlite-storage-choice")

    ExUnit.Callbacks.on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    use_runtime_storage_profile!(runtime)

    context
    |> establish_identity(:admin)
    |> open("/storage")
    |> Map.put(:pointer_bytes_before, pointer_bytes())
  end

  # A fresh installation without a pointer, whose storage profile defaults to the marked
  # run's own SQLite directory; no database exists there yet.
  def prepare_behaviour(context, :empty_isolated_database, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])
    runtime = TestRuntimeRoot.create!("sqlite-storage-schema")

    ExUnit.Callbacks.on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    use_runtime_storage_profile!(runtime)
    database = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    if File.exists?(database), do: raise("the isolated database already exists")

    Map.merge(context, %{flat_root: runtime.path, sqlite_database_path: database})
  end

  # A flat-primary installation without a pointer, whose storage profile defaults to the
  # marked run's own SQLite directory.
  def prepare_behaviour(context, :flat_primary_default_location, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])
    runtime = TestRuntimeRoot.create!("sqlite-storage-migration")

    ExUnit.Callbacks.on_exit(fn ->
      SqliteCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    use_runtime_storage_profile!(runtime)
    identity = seed_flat_fixtures!(runtime.path)

    Map.merge(context, %{
      flat_root: runtime.path,
      runtime_sqlite_root: runtime.sqlite_path,
      sqlite_database_path: Path.join(runtime.sqlite_path, "bnest.sqlite3"),
      migration_identity: identity
    })
  end

  # The managed migration was interrupted after its first record write, as a killed process
  # would leave it: the ledger holds the path-first source's accepted item and nothing for
  # the rest.
  def prepare_behaviour(context, :migration_stopped_after_progress, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])
    previous = InterruptedMigrationLedger.install(1)

    interrupted? =
      try do
        Storage.migrate(context.flat_root, false)
        false
      rescue
        _interruption in RuntimeError -> true
      after
        InterruptedMigrationLedger.uninstall(previous)
      end

    [first | remaining] = StorageMigration.inventory(context.flat_root)
    first_item = migration_item_rows(first)

    unless interrupted? and match?([_item], first_item) and
             Enum.all?(remaining, &(migration_item_rows(&1) == [])),
           do: raise("the migration did not stop after its first accepted item")

    Map.merge(context, %{
      first_migrated_path: first,
      remaining_paths: remaining,
      first_item_before_retry: first_item,
      first_record_before_retry: migrated_record_rows(first)
    })
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
      migration_run_result: StorageMigration.run(flat_root)
    })
  end

  def prepare_behaviour(context, :malformed_or_changed_source, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])
    broken_path = Path.join(context.flat_root, "system/manifests/broken-manifest.json")
    File.mkdir_p!(Path.dirname(broken_path))
    File.write!(broken_path, "not-json")

    Map.merge(context, %{
      broken_source: "system/manifests/broken-manifest.json",
      flat_tree_before: flat_tree_digests(context.flat_root)
    })
  end

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
    StorageMigration.run(flat_root)
    :ok = StorageMigration.activate!()

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

  # No override saved: the scenario's configuration path names a file nothing writes, so the
  # destination resolves to the repository default of this run's own isolated root.
  def prepare_behaviour(context, :test_environment, _args) do
    context
    |> prepare_backup_destination()
    |> BackupIntegrity.prepare(:test_environment, [])
  end

  # A real temporary destination, saved as the configured one, in the isolated ledger database.
  def prepare_behaviour(context, state, args) when state in @integrity_destination_prepares do
    ensure_scheduler_storage()
    location = TestBackupDestination.configure!("integrity")

    context
    |> Map.merge(%{backup_directory: location.directory, backup_location: location})
    |> BackupIntegrity.prepare(state, args)
  end

  def prepare_behaviour(context, state, args) when state in @integrity_prepares,
    do: BackupIntegrity.prepare(context, state, args)

  # A real temporary destination, saved as the configured one: the restore drill reads it and
  # the artifacts it restores are real SQLite files in it.
  def prepare_behaviour(context, state, args) when state in @drill_destination_prepares do
    location = TestBackupDestination.configure!("restore-drill")

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
      |> open_label_view()

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

  # --- phase-8 FE ADD rows ---

  # BN-STORAGE-05/06/07: the administrator's storage page over the current
  # flat-primary instance. The `@flat-primary` hook spawns the instance, so
  # the fresh state needs no seed; the blocked and active states migrate it.
  def prepare_behaviour(context, :storage_setup, ["fresh flat-primary"]) do
    unless Storage.phase() == :flat_primary,
      do: raise("the fresh instance is not flat-primary")

    context
  end

  def prepare_behaviour(context, :storage_setup, ["blocked migration"]) do
    root = instance_flat_root!()
    broken = Path.join(root, "system/manifests/broken-manifest.json")
    File.mkdir_p!(Path.dirname(broken))
    File.write!(broken, "{malformed")

    case Storage.migrate(root, false) do
      {:error, :blocked, _report} ->
        context

      outcome ->
        raise "the malformed source did not block the migration: #{inspect(outcome)}"
    end
  end

  def prepare_behaviour(context, :storage_setup, ["active SQLite"]) do
    root = instance_flat_root!()

    case Storage.migrate(root, true) do
      {:ok, :activated, _report} ->
        context

      outcome ->
        raise "the seeded instance did not migrate and activate: #{inspect(outcome)}"
    end
  end

  def prepare_behaviour(context, :storage_seeded_with_malformed, _args) do
    root = instance_flat_root!()
    broken = Path.join(root, "system/manifests/broken-manifest.json")
    File.mkdir_p!(Path.dirname(broken))
    File.write!(broken, "{malformed")
    open_storage_page(context)
  end

  def prepare_behaviour(context, :storage_migration_in_progress, _args) do
    root = instance_flat_root!()

    with {:ok, _outcome, _report} <- Storage.migrate(root, false),
         true <- Storage.migration_started?() do
      context
    else
      outcome -> raise "the seeded migration did not start: #{inspect(outcome)}"
    end
  end

  def prepare_behaviour(context, :write_session_refused, _args) do
    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:bnest_app, :refuse_workspace_write)
    end)

    Application.put_env(:bnest_app, :refuse_workspace_write, true)
    context
  end

  def prepare_behaviour(context, :model_missing_for_role, [model, role]) do
    context = establish_identity(context, role_atom(role))
    hide_model(models_without(model))
    context
  end

  def prepare_behaviour(context, :transcript_saves_rejected, _args),
    do: install_failing_transcript_store(context, :refused)

  def prepare_behaviour(context, :transcript_saves_stale, _args),
    do: install_failing_transcript_store(context, :stale)

  def prepare_behaviour(context, :generated_image_saved, [file]) do
    ensure_generated_images()
    InMemoryGeneratedImages.put_file(generated_reference(file), synthetic_png())
    context
  end

  def prepare_behaviour(context, :generated_jpeg_saved, [file]) do
    ensure_generated_images()
    InMemoryGeneratedImages.put_file(generated_reference(file), synthetic_jpeg())
    context
  end

  def prepare_behaviour(context, :generated_images_cleared, _args) do
    ensure_generated_images()
    context
  end

  def prepare_behaviour(context, state, args),
    do: IntegrationFamilyChatDriver.prepare_behaviour(context, state, args)

  defp ensure_generated_images do
    unless GenServer.whereis(InMemoryGeneratedImages) do
      swap_generated_images_adapter()
      :ok = InMemoryGeneratedImages.install()
    end

    :ok
  end

  defp role_atom("child"), do: :child
  defp role_atom("parent"), do: :parent

  defp models_without("Luna"),
    do: Enum.reject(FixtureModels.all(), &(&1.id == "gpt-6-luna"))

  defp models_without("Terra"),
    do: Enum.reject(FixtureModels.all(), &(&1.id == "gpt-6.1-terra"))

  # The application boots one shared model catalog; the scenario hides one model from it and
  # hands it back afterwards.
  defp hide_model(models) do
    previous = :sys.get_state(ModelCatalog)

    ExUnit.Callbacks.on_exit(fn ->
      :sys.replace_state(ModelCatalog, fn _state -> previous end)
    end)

    :sys.replace_state(ModelCatalog, fn state ->
      %{state | models: models, by_id: Map.new(models, &{&1.id, &1})}
    end)
  end

  defp install_failing_transcript_store(context, mode) do
    owner = context.user_id
    before = CodexChat.load_transcript(owner)

    records =
      case before do
        {:ok, _transcript, record} -> %{owner => record}
        {:error, _reason} -> %{}
      end

    :ok = InMemoryFailingTranscriptStore.install(records)
    previous_chat = Application.fetch_env!(:bnest_app, CodexChat)

    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:bnest_app, CodexChat, previous_chat) end)

    Application.put_env(
      :bnest_app,
      CodexChat,
      Keyword.put(previous_chat, :transcript_store, InMemoryFailingTranscriptStore)
    )

    previous_mode = Application.get_env(:bnest_app, :transcript_write_outcome)

    ExUnit.Callbacks.on_exit(fn ->
      if is_nil(previous_mode),
        do: Application.delete_env(:bnest_app, :transcript_write_outcome),
        else: Application.put_env(:bnest_app, :transcript_write_outcome, previous_mode)
    end)

    Application.put_env(:bnest_app, :transcript_write_outcome, mode)
    Map.put(context, :transcript_before, before)
  end

  defp swap_generated_images_adapter do
    previous_chat = Application.fetch_env!(:bnest_app, CodexChat)

    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:bnest_app, CodexChat, previous_chat) end)

    Application.put_env(
      :bnest_app,
      CodexChat,
      Keyword.put(previous_chat, :generated_images, InMemoryGeneratedImages)
    )
  end

  @generated_thread "abcdef12-3456"

  defp generated_reference(file), do: @generated_thread <> "/" <> file

  defp synthetic_png, do: <<0x89, "PNG\r\n", 0x1A, "\n">> <> "synthetic generated image"

  defp synthetic_jpeg, do: <<0xFF, 0xD8, 0xFF, 0xE0>> <> "synthetic generated photo"

  @impl true
  def perform_behaviour(context, :open_protected_route, [route]) do
    {response, record_accesses} = record_accesses_during(fn -> get(context.conn, route) end)
    redirected = login_redirect_returning_to?(response, route)

    login_response =
      if redirected,
        do: response |> recycle() |> get(redirected_to(response)),
        else: response

    login_form_only =
      login_response.status == 200 and
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

  # The submissions are the evidence: each password missing a letter, number or punctuation
  # mark is submitted on its own first and must leave setup open, then the real accounts use
  # a three-character and a 131-character password, and each must log in afterwards.
  def perform_behaviour(context, :bootstrap_accounts, _args) do
    {rejections, first_result, second_result, logins} =
      submit_initial_accounts(context.identity_store)

    Map.merge(context, %{
      bootstrap_rejections: rejections,
      bootstrap_first_result: first_result,
      bootstrap_second_result: second_result,
      bootstrap_logins: logins
    })
  end

  # The login form posts to the session controller, and its redirect is followed with every
  # cookie it set, as a browser does; both requests run with every log line captured.
  def perform_behaviour(context, :login, _args) do
    params = %{
      "login" => %{
        "username" => context.identity_username,
        "password" => context.identity_password
      }
    }

    {{login_response, token, home_response}, log} =
      with_debug_log(fn ->
        response = post(build_conn(), "/login", params)
        token = response.resp_cookies["_bnest_identity"][:value]
        {response, token, token && get(recycle(response), redirected_to(response))}
      end)

    Map.merge(context, %{
      token: token,
      login_response: login_response,
      home_response: home_response,
      login_log: log
    })
  end

  def perform_behaviour(context, :logout_current_browser, _args) do
    response =
      build_conn()
      |> Plug.Test.put_req_cookie("_bnest_identity", context.token)
      |> delete("/logout")

    Map.put(context, :logout_response, response)
  end

  # The login form posts its hidden return path with the credentials, so the
  # redirect the controller answers is the evidence.
  def perform_behaviour(context, :login_with_return_path, [return_to]) do
    params = %{
      "login" => %{
        "username" => context.identity_username,
        "password" => context.identity_password
      },
      "return_to" => login_return_path(return_to)
    }

    Map.put(context, :login_response, post(build_conn(), "/login", params))
  end

  def perform_behaviour(context, :login_wrong_password, _args) do
    params = %{
      "login" => %{
        "username" => context.identity_username,
        "password" => "Definitely the wrong password 0!"
      }
    }

    Map.put(context, :login_response, post(build_conn(), "/login", params))
  end

  def perform_behaviour(context, :login_unknown_user, _args) do
    params = %{
      "login" => %{
        "username" => "test-user-integration-unknown",
        "password" => context.identity_password
      }
    }

    Map.put(context, :login_response, post(build_conn(), "/login", params))
  end

  # An unsigned browser opens home through the endpoint, so the pipeline's own
  # guards decide between the legacy home page and the login redirect. The
  # redirect flag is the one the shared login-redirect outcome reads.
  def perform_behaviour(context, :visit_home, _args) do
    response = get(context.conn, "/")

    Map.merge(context, %{home_response: response, redirected: login_redirect?(response)})
  end

  # The setup shell the endpoint renders for an open bootstrap: the
  # integration layer owns no browser scripting, so it proves the shell the
  # JavaScript dynamics (covered by the vitest scenario and the e2e
  # click-through) start from.
  def perform_behaviour(context, :show_setup, _args) do
    response = get(context.conn, "/setup")
    page = LazyHTML.from_document(response.resp_body)
    Map.merge(context, %{setup_response: response, setup_page: page})
  end

  # A setup submission that breaks one rule, posted to the bootstrap
  # controller on the scenario's open flat-primary instance.
  def perform_behaviour(context, :submit_setup_case, [setup_case]) do
    response = post(context.conn, "/setup", setup_case_params(setup_case))
    followup = response |> recycle() |> get("/setup")
    Map.merge(context, %{setup_response: response, setup_followup: followup})
  end

  # Two cards whose confirmations differ: the refusal must keep the names and
  # roles while clearing every password.
  def perform_behaviour(context, :submit_mismatched_setup, _args) do
    params = %{
      "confirm" => "closed",
      "accounts" => %{
        "0" =>
          setup_account_params("test-user-setup-one", "Setup password 1!", "Setup mismatch 9!", [
            "children"
          ]),
        "1" =>
          setup_account_params("test-user-setup-two", "Setup password 2!", "Setup mismatch 8!", [
            "admin"
          ])
      }
    }

    response = post(context.conn, "/setup", params)
    followup = response |> recycle() |> get("/setup")
    Map.merge(context, %{setup_response: response, setup_followup: followup})
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

  # The first user's theme read and write aimed at the second owner, each guarded by the
  # authorization a request handler applies before it reaches the Preferences facade, inside
  # the record trace.
  def perform_behaviour(context, :cross_user_operation, _args) do
    {attempts, accesses} =
      record_accesses_during(fn ->
        cross_user_theme_attempts(context.first_user, context.second_owner)
      end)

    Map.merge(context, %{
      cross_user_attempts: attempts,
      cross_user_accesses: accesses,
      second_theme_after: Preferences.theme(context.second_owner)
    })
  end

  # The routed import page receives the browser's report through its hook and the user's
  # confirmation through its button; the rendered outcome lines and the cleanup instruction
  # pushed back are the user's evidence.
  def perform_behaviour(context, :confirm_imports, _args) do
    {:ok, view, _html} = live(context.conn, "/data-migration")
    render_hook(view, "browser-sources", %{"sources" => context.browser_sources})
    html = view |> element("button[phx-click=confirm-imports]") |> render_click()
    %{proxy: {ref, _topic, _pid}} = view

    cleared =
      receive do
        {^ref, {:push_event, "imports-accepted", %{"storageKeys" => keys}}} -> keys
      after
        1_000 -> raise "the import page sent no cleanup instruction"
      end

    outcomes =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[aria-live=polite] p")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    Map.merge(context, %{import_outcomes: outcomes, cleared_storage_keys: cleared})
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

  # The user changes the theme after the accepted import, through the routed theme endpoint the
  # root layout's script uses. The change and the home it leaves are read by
  # `:server_only_persistence`.
  def perform_behaviour(context, :change_theme, _args) do
    before = FileRecordBackend.read(context.central_store, :theme, context.user_id)
    change = context.conn |> recycle() |> put("/preferences/theme", %{"theme" => "dark"})
    Map.merge(context, %{theme_before: before, theme_change_status: change.status})
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

    # Request a non-normalized spelling of the same folder so the normalization Then observes work.
    persist_storage_from_view(context, custom <> "/../" <> Path.basename(custom) <> "/")
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

  # The managed migration applies the committed migration set each time it starts; it starts
  # twice over the empty installation, and the schema is read after each start.
  def perform_behaviour(context, :apply_migration_set_twice, _args) do
    first = Storage.migrate(context.flat_root, false)
    after_first = sqlite_schema_state()
    second = Storage.migrate(context.flat_root, false)

    Map.merge(context, %{
      schema_applies: [first, second],
      schema_after_first_apply: after_first,
      schema_after_second_apply: sqlite_schema_state()
    })
  end

  def perform_behaviour(context, :run_managed_storage_migration, _args) do
    outcome = Storage.migrate(context.flat_root, false)

    Map.merge(context, %{
      migration_outcome: outcome,
      migration_run_result: elem(outcome, 2).run
    })
  end

  def perform_behaviour(context, :retry_same_migration, _args) do
    outcome = Storage.migrate(context.flat_root, false)
    first = context.first_migrated_path

    Map.merge(context, %{
      migration_outcome: outcome,
      first_item_after_retry: migration_item_rows(first),
      first_record_after_retry: migrated_record_rows(first)
    })
  end

  def perform_behaviour(context, :commit_authority_switch, _args) do
    sqlite_repo_started!(context.sqlite_database_path)
    :ok = StorageMigration.activate!()
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

  # Verification is the managed migration with the authority switch requested; an
  # administrator then opens the storage page.
  def perform_behaviour(context, :verify_migration, _args) do
    outcome = Storage.migrate(context.flat_root, true)
    storage_page = context |> establish_identity(:admin) |> open("/storage")

    Map.merge(context, %{
      migration_outcome: outcome,
      storage_status_html: render(storage_page.view),
      flat_tree_after: flat_tree_digests(context.flat_root)
    })
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

  # The admin route is requested inside the record trace, which must see no record call but
  # the visitor's own session, account and theme reads the browser pipeline makes. The home
  # page is then read as the same visitor.
  def perform_behaviour(context, :open_denied_route, [path]) do
    {response, accesses} = record_accesses_during(fn -> get(context.conn, path) end)
    home = get(context.conn, "/")

    Map.merge(context, %{
      denied_response: response,
      denied_accesses: accesses,
      home_response: home
    })
  end

  # The page shows the backup destination, so it is given an isolated working default: the
  # test run's own repository root fails closed, and the page would fall back to an empty
  # inventory.
  def perform_behaviour(context, :open_schedules_from_home, _args) do
    _default = TestBackupDestination.default_repository!("schedules-" <> unique_suffix())
    Map.put(context, :response, follow_home_entry(context.conn, "admin-schedules-entry"))
  end

  def perform_behaviour(context, :open_admin_settings_from_home, _args),
    do: Map.put(context, :response, follow_home_entry(context.conn, "admin-settings-entry"))

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

  # The administrator submits the page's backup folder form twice with the same folder, as
  # a double click would; the first verification each save queues runs to completion.
  def perform_behaviour(context, :save_backup_override, _args) do
    params = %{"backup" => %{"destination_directory" => context.backup_directory}}

    html =
      Enum.reduce(1..2, nil, fn _submit, _html ->
        context.schedules_view
        |> form("form[phx-submit=save_backup]", params)
        |> render_submit()
      end)

    await_scheduler_tasks()
    ensure_scheduler_storage()
    Map.merge(context, %{schedules_html: html, backup_destination: Backup.destination()})
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

    Map.merge(context, %{
      reconciled_claims: Enum.filter(claims, &(&1.schedule_key == context.schedule_key)),
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

  # The page as a connected administrator opens it: the first render, then the render once
  # the check it started has reported.
  def perform_behaviour(context, :open_schedules_label, args),
    do: context |> open_label_view() |> note_viewport(args)

  # One of the page's forms submitted with the fields as rendered: the label is read right
  # after the event and again once the check the save started has reported.
  # BN-ADMIN-04 and BN-ADMIN-05: the schedule form submitted as rendered, so its
  # hidden revision is the page's own. After a rival save that revision is stale
  # and the page reports the conflict instead.
  def perform_behaviour(context, :save_schedule_with_time, [time]) do
    html =
      context.schedules_view
      |> form("form[phx-submit=save_schedule]", %{
        "schedule" => %{"daily_time_wib" => time, "enabled" => "true"}
      })
      |> render_submit()

    Map.put(context, :schedules_result_html, LazyHTML.from_fragment(html))
  end

  def perform_behaviour(context, :rival_schedule_save, [time]) do
    {:ok, rival} =
      Scheduler.update_daily(
        context.schedule_key,
        %{
          "daily_time_wib" => time,
          "enabled" => "true",
          "revision" => Integer.to_string(context.saved_schedule.revision)
        },
        DateTime.utc_now() |> DateTime.truncate(:second)
      )

    Map.put(context, :rival_schedule, rival)
  end

  # BN-ADMIN-06: the backup folder form submitted with a folder of the outline's
  # kind, each created under the run's temporary root.
  def perform_behaviour(context, :save_backup_folder, [kind]) do
    directory = backup_folder_for!(kind)

    html =
      context.schedules_view
      |> form("form[phx-submit=save_backup]", %{
        "backup" => %{"destination_directory" => directory}
      })
      |> render_submit()

    Map.merge(context, %{
      schedules_result_html: LazyHTML.from_fragment(html),
      attempted_folder: directory
    })
  end

  # BN-DATA-10: the cutover-off visitor opening the migration page is redirected
  # home with the login warning. The LiveView redirect is asserted first, then the
  # routed home page carrying the warning without any import control.
  def perform_behaviour(context, :open_migration_cutover_off, _args) do
    previous = Application.fetch_env!(:bnest_app, :identity_cutover_enabled)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, :identity_cutover_enabled, previous)
    end)

    Application.put_env(:bnest_app, :identity_cutover_enabled, false)

    {:error, {:redirect, %{to: "/"}}} = live(build_conn(), "/data-migration")

    redirected = build_conn() |> get("/data-migration")
    home = redirected |> recycle() |> get("/")

    Map.merge(context, %{migration_redirect: redirected, migration_home: home})
  end

  def perform_behaviour(%{sifat_ready_user: :account} = context, :open_revision_page, _args) do
    {:ok, view, _html} = live(context.conn, "/apps/sifat-allah")
    Map.put(context, :view, view)
  end

  def perform_behaviour(%{sifat_ready_user: :browser} = context, :open_revision_page, _args) do
    {:ok, view, _html} = live(build_conn(), "/apps/sifat-allah")
    Map.put(context, :view, view)
  end

  def perform_behaviour(context, :reject_progress_saves, _args) do
    previous = Application.fetch_env!(:bnest_app, BnestApp.SifatAllah)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, BnestApp.SifatAllah, previous)
    end)

    Application.put_env(
      :bnest_app,
      BnestApp.SifatAllah,
      Keyword.put(previous, :progress_store, BnestApp.Behaviour.FailingProgressStore)
    )

    Map.put(context, :sifat_store_previous, previous)
  end

  # The single rejected save: the store fails this write, then it is healthy again
  # so the reload below reads the earlier saved progress.
  def perform_behaviour(context, :mark_pair_while_failing, _args) do
    html = context.view |> element("button", "Aku sudah ingat") |> render_click()
    Application.put_env(:bnest_app, BnestApp.SifatAllah, context.sifat_store_previous)
    Map.put(context, :sifat_failed_html, LazyHTML.from_fragment(html))
  end

  def perform_behaviour(context, :save_label_form, [form]) do
    view = context.schedules_view

    after_save =
      view |> form("form[phx-submit=#{label_form_event(form)}]") |> render_submit()

    settled = render_async(view, IntegrityLabel.settle_ms())
    await_scheduler_tasks()

    Map.merge(context, %{
      label_after_save: LazyHTML.from_fragment(after_save),
      label_settled_after_save: LazyHTML.from_fragment(settled)
    })
  end

  def perform_behaviour(context, :open_and_reload_label, []) do
    evidence = %{
      destination: BackupIntegrity.snapshot(context.backup_directory),
      ledger: BackupIntegrity.readable_ledger()
    }

    context |> open_label_view() |> open_label_view() |> Map.put(:evidence_before, evidence)
  end

  def perform_behaviour(context, :read_label_and_report, []),
    do: context |> open_label_view() |> BackupIntegrity.run_task(&reconcile_task/0)

  # The page is opened over a check that never finishes: the first render is read at once,
  # and the result only when the page's ceiling ends the check.
  def perform_behaviour(context, :open_label_past_ceiling, []) do
    started = IntegrityLabel.now()
    context = open_label_view(context)

    Map.put(context, :ceiling, IntegrityLabel.observe_ceiling(IntegrityLabel.now() - started))
  end

  # The visitor's request is stopped by the router's admin guard. The artifact reads it
  # caused are counted, and so are the reads of an administrator's visit to the same route:
  # the probe sees a reconciliation when one runs, so no reads for the visitor is a measurement.
  def perform_behaviour(context, :open_schedules_route_denied, []) do
    reads = ObservedArtifactStore.read_count()

    {response, accesses} =
      record_accesses_during(fn -> get(context.conn, @schedules_route) end)

    denied = ObservedArtifactStore.read_count() - reads

    {administrator, _identity} =
      BnestAppWeb.ConnCase.scenario_authenticated_conn(
        Phoenix.ConnTest.build_conn(),
        "#{context.feature_file}:#{context.scenario_name}:label-control",
        ["admin"]
      )

    reads = ObservedArtifactStore.read_count()
    _control = open_label_view(%{context | conn: administrator})
    control = ObservedArtifactStore.read_count() - reads

    Map.merge(context, %{
      response: response,
      response_accesses: accesses,
      denied_response: response,
      denied_accesses: accesses,
      denied_reads: denied,
      control_reads: control
    })
  end

  # The reconcile task's own entry point, in this VM over the isolated ledger and destination.
  def perform_behaviour(context, :reconcile_task, _args),
    do: BackupIntegrity.run_task(context, &reconcile_task/0)

  def perform_behaviour(context, :read_report_and_log, _args),
    do: BackupIntegrity.read_report_and_log(context, &reconcile_task/0)

  def perform_behaviour(context, action, args) when action in @integrity_performs,
    do: BackupIntegrity.perform(context, action, args)

  def perform_behaviour(context, action, args) when action in @drill_performs,
    do: RestoreDrill.perform(context, action, args)

  # --- phase-8 FE ADD rows ---

  # The same browser session jar the first mount authenticated with, so the second mount
  # restores the same owner's transcript the way another tab would.
  def perform_behaviour(context, :open_second_session, [route]) do
    {:ok, second_view, _html} = live(context.conn, route)

    Map.merge(context, %{second_conn: context.conn, second_view: second_view, second_route: route})
  end

  def perform_behaviour(context, :runner_event, [event]) do
    send(context.view.pid, {:codex, context.view.pid, {:error, RunnerEvent.message_for(event)}})
    render(context.view)
    context
  end

  # BN-STORAGE-05/06/07: opens the production storage page as the
  # administrator and presses its migration control. The control submits the
  # same managed migration the page triggers, over the current instance.
  def perform_behaviour(context, :open_storage_page, _args) do
    open_storage_page(context)
  end

  def perform_behaviour(context, :press_storage_control, ["Move data"]) do
    html = render_submit(context.storage_view, :move_data, %{})
    Map.put(context, :storage_status_html, html)
  end

  def perform_behaviour(context, :press_storage_control, ["Retry migration"]) do
    html = render_submit(context.storage_view, :retry_migration, %{})
    Map.put(context, :storage_status_html, html)
  end

  # The operator repairs the source by removing the malformed file, the way
  # deleting a broken hand-written file on the host would; the retry then
  # runs the same managed migration the control triggers.
  def perform_behaviour(context, :repair_and_retry, [_label]) do
    broken = Path.join(instance_flat_root!(), "system/manifests/broken-manifest.json")
    File.rm!(broken)
    html = render_submit(context.storage_view, :retry_migration, %{})
    Map.put(context, :storage_status_html, html)
  end

  def perform_behaviour(context, :request_generated_image, [file]) do
    request_generated_image(context, generated_route(file))
  end

  def perform_behaviour(context, :request_generated_image_encoded, [file]) do
    request_generated_image(context, generated_encoded_route(file))
  end

  def perform_behaviour(context, :request_generated_image_path, [path]) do
    request_generated_image(context, "/chat/generated-images/" <> path)
  end

  def perform_behaviour(context, :request_service_worker, _args) do
    response = get(context.conn, "/service-worker.js")

    Map.merge(context, %{
      service_worker_response: response,
      service_worker_body: response.resp_body
    })
  end

  def perform_behaviour(context, :complete_image_reply, _args) do
    {prompt, session, context} = unanswered_prompt!(context)

    {events, threads} =
      CodexFixtureConversation.answer(Map.get(context, :codex_threads, %{}), session, prompt)

    context = context |> Map.put(:codex_threads, threads) |> deliver_codex_events(events)
    _snapshot = await_push_event(context.view, "persist-chat")
    context
  end

  def perform_behaviour(context, :sign_out, _args) do
    Map.merge(context, %{authenticated: false, conn: Phoenix.ConnTest.build_conn()})
  end

  def perform_behaviour(context, action, args),
    do: IntegrationFamilyChatDriver.perform_behaviour(context, action, args)

  # The current flat-primary instance's flat root, which the storage page
  # migrates and the scenario seeds.
  defp instance_flat_root! do
    case BnestApp.TestInstance.state() do
      %{paths: %{flat_instance_root: root}} -> root
      _other -> raise "no flat-primary test instance is current"
    end
  end

  defp open_storage_page(context) do
    storage_page = context |> establish_identity(:admin) |> open("/storage")

    Map.merge(context, %{
      storage_view: storage_page.view,
      storage_status_html: render(storage_page.view)
    })
  end

  defp request_generated_image(context, route) do
    Map.merge(context, %{image_response: get(context.conn, route), image_request_path: route})
  end

  defp generated_route(file),
    do: "/chat/generated-images/" <> @generated_thread <> "/" <> file

  defp generated_encoded_route(file) do
    "/chat/generated-images/" <>
      URI.encode(@generated_thread <> "/" <> file, &URI.char_unreserved?/1)
  end

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
    do: accepted_any_length?(context)

  def behaviour_outcome?(context, :password_requirements_enforced, _args),
    do: rejected_each_missing_requirement?(context.bootstrap_rejections)

  def behaviour_outcome?(context, :protected_home_available, _args),
    do: protected_home?(context.home_response) and protected_home?(browser_home(context.token))

  # The controller redirects a valid login to the posted return path, or to
  # the site root when the path would leave this site.
  def behaviour_outcome?(context, :landed_on, [path]),
    do: redirected_to(context.login_response) == path

  # A wrong password and an unknown username share the safe refusal: back to
  # the login page with one alert, and no identity cookie.
  def behaviour_outcome?(context, :invalid_login_alert, _args) do
    response = context.login_response

    redirected_to(response) == "/login" and
      Phoenix.Flash.get(response.assigns.flash, :error) ==
        "Username or password is not valid."
  end

  def behaviour_outcome?(context, :no_identity_cookie, _args),
    do: context.login_response.resp_cookies["_bnest_identity"] == nil

  # With cutover off the unsigned browser is the legacy local user: the
  # status names it, no log out control is offered, and the migration note
  # says chat and progress stay in this browser.
  def behaviour_outcome?(context, :local_browser_user, _args) do
    case context.home_response do
      %{status: 200, resp_body: body} ->
        String.contains?(body, "Local browser") and
          not String.contains?(body, "Log out") and
          String.contains?(body, "remain in this browser")

      _other ->
        false
    end
  end

  # The setup shell for an open bootstrap: exactly one administrator card.
  def behaviour_outcome?(context, :one_admin_card, _args) do
    cards = LazyHTML.query(context.setup_page, "[data-account-card]")

    Enum.count(cards) == 1 and
      cards |> Enum.at(0) |> LazyHTML.text() |> String.contains?("Initial administrator")
  end

  def behaviour_outcome?(context, :first_card_no_remove, _args) do
    context.setup_page
    |> LazyHTML.query("[data-account-card]")
    |> Enum.at(0)
    |> LazyHTML.query("[data-remove-account]")
    |> Enum.empty?()
  end

  def behaviour_outcome?(context, :offers_add_account, _args) do
    context.setup_page |> LazyHTML.query("[data-add-account]") |> Enum.any?() and
      String.contains?(context.setup_response.resp_body, "account-card-template")
  end

  def behaviour_outcome?(context, :template_numbers_card, _args) do
    body = context.setup_response.resp_body

    String.contains?(body, "accounts[__INDEX__][username]") and
      String.contains?(body, "data-account-number")
  end

  # A refused setup redirects back to the setup page with the rule's message,
  # and the followed page still answers the open setup form.
  def behaviour_outcome?(context, :setup_refused, [message]) do
    response = context.setup_response

    redirected_to(response) == "/setup" and
      Phoenix.Flash.get(response.assigns.flash, :error) == message and
      match?(%{status: 200}, context.setup_followup) and
      String.contains?(context.setup_followup.resp_body, "bootstrap-form")
  end

  def behaviour_outcome?(_context, :no_account_created, _args),
    do: BnestApp.Identity.setup_status() == :open

  # The refused re-render keeps both usernames and ticked roles.
  def behaviour_outcome?(context, :setup_keeps_names_roles, _args) do
    body = context.setup_followup.resp_body

    String.contains?(body, "test-user-setup-one") and
      String.contains?(body, "test-user-setup-two") and
      role_checked?(body, "0", "children") and
      role_checked?(body, "1", "admin")
  end

  def behaviour_outcome?(context, :passwords_cleared, _args) do
    body = context.setup_followup.resp_body

    not String.contains?(body, "Setup password 1!") and
      not String.contains?(body, "Setup password 2!") and
      not String.contains?(body, "Setup mismatch 9!") and
      not String.contains?(body, "Setup mismatch 8!")
  end

  def behaviour_outcome?(context, :refusal_alert, _args) do
    body = context.setup_followup.resp_body

    String.contains?(body, "Each password and confirmation must match.") and
      String.contains?(body, "setup-error")
  end

  def behaviour_outcome?(context, :current_browser_logged_out, _args),
    do:
      login_redirect?(context.logout_response) and login_redirect?(browser_home(context.token)) and
        BnestApp.Identity.current_user(context.token) == {:error, :unauthenticated}

  # The verifier is the real hasher's Argon2id hash of the password, and neither the stored
  # record files, the log captured at debug level across the login and home requests, nor
  # either response holds the plaintext.
  def behaviour_outcome?(context, :no_plaintext_password, _args) do
    password = context.identity_password

    bytes = instance_stored_bytes()

    rendered = context.login_response.resp_body <> context.home_response.resp_body

    protected_home?(context.home_response) and
      String.contains?(context.login_log, "Processing with BnestAppWeb.SessionController.create") and
      String.starts_with?(context.verifier, "$argon2id$") and
      Argon2CredentialHasher.verify(password, context.verifier) and
      not String.contains?(bytes, password) and
      not String.contains?(context.login_log, password) and
      not String.contains?(rendered, password)
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

  # The trace saw no record call naming the second owner, and the second owner's theme is what
  # it was. The attempts may be refused, or may write only the first user's own record.
  # The read and the write both ran, so the outcome cannot pass on an attempt that never happened.
  def behaviour_outcome?(context, :second_user_data_unchanged, _args) do
    owner = context.second_owner

    Keyword.keys(context.cross_user_attempts) == [:read_theme, :write_theme] and
      not Enum.any?(context.cross_user_accesses, &names_owner?(&1, owner)) and
      context.second_theme_after == context.second_theme_before and
      context.second_theme_before == "dark"
  end

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

  def behaviour_outcome?(context, :validated_location_stored_privately, _args) do
    with {:ok, bytes} <- File.read(FileConfigStore.pointer_path()),
         {:ok, stored} <- Jason.decode(bytes) do
      Enum.sort(Map.keys(stored)) ==
        Enum.sort(~w(databaseDirectory databaseFilename migrationId phase schemaVersion)) and
        Path.type(stored["databaseDirectory"]) == :absolute and
        stored["databaseDirectory"] == Path.expand(context.requested_directory) and
        permission_bits(FileConfigStore.pointer_path()) == 0o600
    else
      _failure -> false
    end
  end

  def behaviour_outcome?(context, :safe_correction_explained, _args),
    do:
      context.unsafe_response
      |> LazyHTML.query("[role=alert]")
      |> LazyHTML.text()
      |> String.contains?("Enter an absolute server-local folder")

  # The pointer's bytes are the same as when the admin opened storage settings. An instance may already hold a
  # pointer, so an absent pointer is not the test.
  def behaviour_outcome?(context, :no_storage_created, _args),
    do: pointer_bytes() == context.pointer_bytes_before

  # The declared migration set is the committed migration files: the run's checksum is their
  # digest, computed here, the applied versions are their versions, and the indexes are
  # exactly the ones they create.
  def behaviour_outcome?(context, :schema_matches_checksum, _args) do
    files =
      sqlite_migrations_path()
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".exs"))
      |> Enum.sort()

    sources = Enum.map(files, &File.read!(Path.join(sqlite_migrations_path(), &1)))
    checksum = :sha256 |> :crypto.hash(Enum.join(sources)) |> Base.encode16(case: :lower)

    versions =
      Enum.map(files, &(&1 |> String.split("_", parts: 2) |> hd() |> String.to_integer()))

    declared_indexes =
      for source <- sources,
          [name] <-
            Regex.scan(~r/CREATE\s+(?:UNIQUE\s+)?INDEX\s+(\w+)/, source, capture: :all_but_first),
          into: MapSet.new(),
          do: name

    state = context.schema_after_first_apply

    Enum.all?(context.schema_applies, &match?({:ok, :dry_run, _report}, &1)) and
      state.runs == [["flat-files-v1-to-sqlite-v1", checksum]] and state.versions == versions and
      state.indexes == declared_indexes
  end

  def behaviour_outcome?(context, :no_duplicate_schema_objects, _args) do
    first = context.schema_after_first_apply
    second = context.schema_after_second_apply

    second == first and length(second.runs) == 1 and second.objects != [] and
      second.versions == Enum.uniq(second.versions)
  end

  def behaviour_outcome?(context, :deterministic_inventory, _args) do
    items = StorageMigration.inventory(context.flat_root)
    items != [] and items == Enum.sort(items)
  end

  # The pointer the migration wrote resolves the database under the marked run's own SQLite
  # directory, which the storage profile names as its default, and the database is there.
  def behaviour_outcome?(context, :database_under_resolved_directory, _args) do
    database = Path.join(context.runtime_sqlite_root, "bnest.sqlite3")

    Storage.default_directory() == context.runtime_sqlite_root and
      FileConfigStore.resolved_database_path() == database and File.regular?(database)
  end

  def behaviour_outcome?(context, :all_valid_items_accepted, _args) do
    inventory_count = context.flat_root |> StorageMigration.inventory() |> length()

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

  # The SQLite record backend the Storage facade hands out returns every inventoried source's
  # record as the source file holds it.
  def behaviour_outcome?(context, :normal_reads_match, _args) do
    {_backend, sqlite} = Storage.record_backend()
    inventory = StorageMigration.inventory(context.flat_root)

    inventory != [] and
      Enum.all?(inventory, fn path ->
        {:ok, {:record, classification}} = FlatMigration.classify_source(path)
        source = context.flat_root |> Path.join(path) |> File.read!() |> Jason.decode!()

        RecordBackend.read(sqlite, classification.type, FlatMigration.identity_of(classification)) ==
          {:ok, source}
      end)
  end

  # The retry left the accepted item's ledger row and migrated record byte-identical and
  # recorded the migration once.
  def behaviour_outcome?(context, :accepted_items_not_duplicated, _args) do
    [[runs]] = SqliteRepo.query!("SELECT count(*) FROM bnest_migration_runs").rows

    context.first_item_after_retry == context.first_item_before_retry and
      context.first_record_after_retry == context.first_record_before_retry and
      length(context.first_record_before_retry) == 1 and runs == 1
  end

  # Every source the interrupted pass never reached now has one accepted item.
  def behaviour_outcome?(context, :remaining_items_continue, _args) do
    count = length(context.remaining_paths) + 1

    context.remaining_paths != [] and
      Enum.all?(context.remaining_paths, fn path ->
        match?([[_path, "accepted"]], migration_item_outcomes(path))
      end) and
      match?({:ok, :dry_run, %{run: %{accepted: ^count, blocked: 0}}}, context.migration_outcome)
  end

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
         {:ok, _conversations, chat} <- CodexChat.load_conversations(user_id),
         true <- chat == context.journey_records.chat,
         conn = Plug.Test.put_req_cookie(Phoenix.ConnTest.build_conn(), "_bnest_identity", token),
         %{status: 200} <- get(conn, "/"),
         %{status: 200} <- get(conn, "/admin/settings"),
         :ok <- BnestApp.Identity.logout(token),
         {:error, :unauthenticated} <- BnestApp.Identity.current_user(token) do
      true
    else
      _failure -> false
    end
  end

  # The switch was attempted and refused, so the pointer never left the flat phase.
  def behaviour_outcome?(context, :sqlite_not_authoritative, _args),
    do:
      match?({:error, :blocked, %{verification: nil}}, context.migration_outcome) and
        FileConfigStore.phase() == :flat_primary

  # Every flat file, the broken one included, keeps its bytes, and the broken one reached no
  # SQLite record.
  def behaviour_outcome?(context, :source_and_service_unchanged, _args) do
    [[copies]] =
      SqliteRepo.query!(
        "SELECT count(*) FROM bnest_records WHERE record_type = 'import-manifest' AND record_key = 'broken-manifest'"
      ).rows

    context.flat_tree_after == context.flat_tree_before and
      Map.has_key?(context.flat_tree_before, context.broken_source) and copies == 0
  end

  # The blocked item carries a value-free category, and the administrator's storage page
  # offers the retry without naming the source, its bytes or the flat root.
  def behaviour_outcome?(context, :value_free_retry_category, _args) do
    page = LazyHTML.from_fragment(context.storage_status_html)

    status =
      page
      |> LazyHTML.query("section[aria-label='Migration status'] strong")
      |> LazyHTML.text()

    migration_item_outcomes(context.broken_source, "error_category") == [
      [context.broken_source, "malformed"]
    ] and status == "Blocked — retry available" and
      not String.contains?(context.storage_status_html, [
        "broken-manifest",
        "not-json",
        context.flat_root
      ])
  end

  def behaviour_outcome?(context, :no_host_path_or_inventory_revealed, _args),
    do: context.denied_response.resp_body == "Not found"

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

  # The page reported each source accepted, and the owner's import directory holds one
  # envelope per source, each keeping the browser payload as given.
  def behaviour_outcome?(context, :immutable_envelopes, _args) do
    envelopes =
      context.central_store.root
      |> Path.join("users/#{context.user_id}/imports/*.json")
      |> Path.wildcard()
      |> Map.new(fn path ->
        envelope = path |> File.read!() |> Jason.decode!()
        {envelope["source"]["storageKey"], envelope}
      end)

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
      case FileRecordBackend.read(context.central_store, type, context.user_id) do
        {:ok, %{"ownerId" => owner}} -> owner == context.user_id
        _missing -> false
      end
    end)
  end

  # The page reported the theme accepted with no browser key to clear, and the run root holds
  # exactly one accepted browser-absence manifest for the owner's theme.
  def behaviour_outcome?(context, :absent_theme_recorded, _args) do
    manifests =
      context.central_store.root
      |> Path.join("system/manifests/*.json")
      |> Path.wildcard()
      |> Enum.map(&(&1 |> File.read!() |> Jason.decode!()))
      |> Enum.filter(&(&1["ownerId"] == context.user_id))

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
      FileRecordBackend.read(context.central_store, :theme, context.user_id) == {:error, :missing}

  def behaviour_outcome?(context, :safe_rejected_import, _args),
    do: context.import_outcomes == ["Chat conversation: rejected safely; browser source retained"]

  # Nothing tells the browser to clear its key, and the server's accepted chat record is the
  # one it held before.
  def behaviour_outcome?(context, :source_and_record_unchanged, _args),
    do:
      context.cleared_storage_keys == [] and
        FileRecordBackend.read(context.central_store, :chat, context.user_id) ==
          context.accepted_before and match?({:ok, _record}, context.accepted_before)

  def behaviour_outcome?(context, :idempotent_import_identity, _args),
    do: match?({:ok, %{import_id: id}} when id == context.first_import_id, context.retry_result)

  # The retry completes the interrupted import once: no second envelope, and the chat record
  # the interruption left absent now exists at its first revision, written from that import.
  def behaviour_outcome?(context, :accepted_data_preserved, _args) do
    chat = FileRecordBackend.read(context.central_store, :chat, context.user_id)

    import_envelope_count(context.central_store, context.user_id) ==
      context.envelopes_before_retry and
      match?({:ok, %{"recordType" => "chat", "revision" => 0}}, chat) and
      match?({:ok, %{"sourceImportId" => id}} when id == context.first_import_id, chat)
  end

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

  # BN-ADMIN-04 and BN-ADMIN-05: the page names the refusal, and the store keeps the
  # save the scenario started from.
  def behaviour_outcome?(context, :schedule_error_shown, [message]) do
    context.schedules_result_html
    |> LazyHTML.query("#settings-error")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(message)
  end

  def behaviour_outcome?(context, :saved_schedule_kept, _args) do
    current = Scheduler.get_schedule(context.schedule_key)

    current.daily_at_utc == context.saved_schedule.daily_at_utc and
      current.revision == context.saved_schedule.revision
  end

  def behaviour_outcome?(context, :no_schedule_success, _args) do
    context.schedules_result_html
    |> LazyHTML.query(".admin-settings-status")
    |> Enum.empty?()
  end

  def behaviour_outcome?(context, :rival_schedule_kept, _args) do
    current = Scheduler.get_schedule(context.schedule_key)

    current.daily_at_utc == context.rival_schedule.daily_at_utc and
      current.revision == context.rival_schedule.revision
  end

  # BN-ADMIN-06: the page names the refusal, and no destination was saved.
  def behaviour_outcome?(context, :backup_error_shown, [message]) do
    context.schedules_result_html
    |> LazyHTML.query("#settings-error")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(message)
  end

  def behaviour_outcome?(context, :backup_nothing_saved, _args) do
    kept = Scheduler.get_schedule(context.schedule_key)

    match?({:error, _reason}, Backup.read_destination()) and kept.claimed_occurrences == 0 and
      context.schedules_result_html
      |> LazyHTML.query(".admin-settings-status")
      |> Enum.empty?()
  end

  # BN-DATA-01: every recognized source is listed with whether this browser holds
  # it, and the foreign key is listed nowhere.
  def behaviour_outcome?(context, :migration_source_listed, [label, status]) do
    context.migration_html
    |> LazyHTML.query(".identity-account-card")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
    |> Enum.any?(&(String.contains?(&1, label) and String.contains?(&1, status)))
  end

  def behaviour_outcome?(context, :migration_no_unknown, _args) do
    context.migration_html |> LazyHTML.text() |> String.contains?("unknown.key") |> Kernel.not()
  end

  # BN-DATA-09: the confirmed import's outcome line, read from the When's own
  # confirmation: confirming again would resume the import and change the outcome.
  def behaviour_outcome?(context, :migration_outcome_shown, [line]),
    do: Enum.member?(Map.get(context, :import_outcomes, []), line)

  # BN-DATA-10: the legacy local user is sent home with the login warning and sees
  # no import control.
  def behaviour_outcome?(context, :migration_login_warning, _args) do
    redirected_to(context.migration_redirect) == "/" and
      context.migration_home.resp_body =~ "Log in before importing browser data."
  end

  def behaviour_outcome?(context, :migration_no_import_control, _args) do
    not (context.migration_home.resp_body =~ "Preserve and verify")
  end

  # BN-SIFAT-16: the failed save is announced in place.
  def behaviour_outcome?(context, :failed_save_notice, _args) do
    context.sifat_failed_html
    |> LazyHTML.query("[role=alert]")
    |> LazyHTML.text()
    |> String.contains?("Progress could not be saved. The previous saved progress is unchanged.")
  end

  def behaviour_outcome?(context, :earlier_progress_shown, _args),
    do: progress_shows?(context, "6 dari 120 soal sudah hafal")

  # BN-SIFAT-17: the storage note for this user.
  def behaviour_outcome?(context, :storage_note_shown, [message]) do
    context.view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".sifat-saved-note")
    |> LazyHTML.text()
    |> String.trim()
    |> Kernel.==(message)
  end

  # A change made after the accepted import: the theme request the root layout's script sends
  # goes through the routed endpoint. It must change the user's record in the server's
  # repository, and the home the server then renders must carry it while telling the browser
  # script to keep no copy of its own.
  def behaviour_outcome?(context, :server_only_persistence, _args) do
    user_id = context.user_id
    requested = "dark"
    stored = FileRecordBackend.read(context.central_store, :theme, user_id)
    home = context.conn |> recycle() |> get("/")
    root = home.resp_body |> LazyHTML.from_document() |> LazyHTML.query("html")

    context.theme_change_status == 204 and stored != context.theme_before and
      match?({:ok, %{"ownerId" => ^user_id, "theme" => ^requested}}, stored) and
      Records.read(:theme, user_id) == stored and Preferences.theme(user_id) == requested and
      home.status == 200 and
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
         {:ok, conversations, record} <- CodexChat.load_conversations(user_id),
         {:ok, %{transcript: transcript}} <- CodexChat.selected_conversation(conversations),
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
      match?(
        {:ok, %{transcript: %{thread_id: nil}}},
        with(
          {:ok, conversations, _} <- CodexChat.load_conversations(context.user_id),
          do: CodexChat.selected_conversation(conversations)
        )
      )
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
    with {:ok, location} <- context.backup_destination,
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

  # The page confirmed the save, and the schedule ledger holds exactly one run claimed for
  # the saved destination however often it was saved.
  def behaviour_outcome?(context, :one_setup_claim, _args) do
    {:ok, %{destination_id: destination_id}} = context.backup_destination

    %{rows: [[setup_runs]]} =
      SqliteRepo.query!("SELECT COUNT(*) FROM bnest_schedule_runs WHERE claim_key = ?", [
        "setup:" <> destination_id
      ])

    String.contains?(
      context.schedules_html,
      "Backup folder saved and its first verification was queued."
    ) and setup_runs == 1
  end

  def behaviour_outcome?(context, :schedule_persisted, _args),
    do: context.scheduler_restarted? and context.schedule_after_restart.enabled

  def behaviour_outcome?(context, :same_future_slot, _args),
    do: context.schedule_after_restart.next_run_at == context.schedule_before_restart.next_run_at

  # Exactly one claim came back for the schedule, for its latest slot, and the ledger holds
  # no other run for it.
  def behaviour_outcome?(context, :latest_slot_only, _args) do
    latest = Policy.latest_slot(context.reconciled_schedule.daily_at_utc, @behaviour_now)

    %{rows: [[stored_runs]]} =
      SqliteRepo.query!("SELECT COUNT(*) FROM bnest_schedule_runs WHERE schedule_key = ?", [
        context.schedule_key
      ])

    match?([%{scheduled_for: ^latest}], context.reconciled_claims) and stored_runs == 1
  end

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

  # The promoted artifact itself is opened read-only and checked here: its quick check, its
  # digest, and its schema versions and logical proof recomputed from its own catalog must
  # be what the receipt claims.
  def behaviour_outcome?(context, :independent_proof, _args) do
    with {:ok, receipt} <- context.backup_execution,
         artifact = Path.join(context.backup_location.directory, receipt["artifactBasename"]),
         {:ok, proof} <- independent_artifact_proof(artifact) do
      proof.quick_check == "ok" and receipt["quickCheck"] == "ok" and
        proof.sha256 == receipt["artifactSha256"] and
        proof.schema_versions == receipt["schemaVersions"] and proof.schema_versions != [] and
        proof.logical_sha256 == receipt["logicalProofSha256"]
    else
      _failure -> false
    end
  end

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

  def behaviour_outcome?(context, :not_found_before_reads, _args) do
    owner = context.user_id

    context.denied_response.status == 404 and
      context.denied_response.resp_body == "Not found" and
      context.denied_accesses != [] and
      Enum.all?(context.denied_accesses, &visitor_own_read?(&1, owner, context.token))
  end

  # Home is the visitor's authenticated page, and it offers no admin entry.
  def behaviour_outcome?(context, :no_admin_home_entry, _args) do
    page = LazyHTML.from_document(context.home_response.resp_body)

    protected_home?(context.home_response) and
      page
      |> LazyHTML.query("[data-role=admin-settings-entry], [data-role=admin-schedules-entry]")
      |> Enum.empty?() and
      not String.contains?(context.home_response.resp_body, "Schedules &amp; backups")
  end

  # The owned receipts are exactly the seven newest runs, newest first, and the two oldest
  # runs' artifacts and receipts are gone from the destination.
  def behaviour_outcome?(context, :owned_retention, _args) do
    {kept, removed} = Enum.split(context.retention_receipts, 7)
    owned = Backup.owned_receipts(context.backup_directory)

    length(removed) == 2 and
      Enum.map(owned, & &1["runId"]) == Enum.map(kept, & &1["runId"]) and
      Enum.all?(removed, fn receipt ->
        artifact = Path.join(context.backup_directory, receipt["artifactBasename"])

        not File.exists?(artifact) and
          not File.exists?(String.replace_suffix(artifact, ".sqlite3", ".receipt.json"))
      end)
  end

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

  def behaviour_outcome?(context, expected, args) when expected in @integrity_outcomes,
    do: BackupIntegrity.outcome?(context, expected, args)

  def behaviour_outcome?(context, expected, args) when expected in @label_outcomes,
    do: IntegrityLabel.outcome?(context, expected, args)

  def behaviour_outcome?(context, expected, args) when expected in @drill_outcomes,
    do: RestoreDrill.outcome?(context, expected, args)

  # --- phase-8 FE ADD rows ---

  # BN-STORAGE-05/06/07: reads the rendered storage page the scenario opened.
  def behaviour_outcome?(context, :storage_page_reads, [text]) do
    status =
      context.storage_status_html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("section[aria-label='Migration status'] strong")
      |> LazyHTML.text()

    status == String.replace_prefix(text, "Status: ", "")
  end

  def behaviour_outcome?(context, :storage_control_reads, [label]) do
    storage_control_label(context.storage_status_html) == label
  end

  def behaviour_outcome?(context, :storage_status_and_control, [status, label]) do
    page = LazyHTML.from_fragment(context.storage_status_html)

    page
    |> LazyHTML.query("section[aria-label='Migration status'] strong")
    |> LazyHTML.text() == String.replace_prefix(status, "Status: ", "") and
      storage_control_label(context.storage_status_html) == label
  end

  def behaviour_outcome?(context, :storage_folder_locked, _args) do
    page = LazyHTML.from_fragment(context.storage_status_html)

    disabled_input? =
      page
      |> LazyHTML.query("input#directory[disabled]")
      |> Enum.any?()

    disabled_check? =
      page
      |> LazyHTML.query("section[aria-label='Database folder'] button[disabled]")
      |> LazyHTML.text()
      |> String.contains?("Check folder")

    disabled_input? and disabled_check? and
      not String.contains?(context.storage_status_html, "Create database")
  end

  def behaviour_outcome?(context, :chat_entry_link_absent, [label, path]) do
    page = context.page
    no_path_link = page |> LazyHTML.query("a[href='#{path}']") |> Enum.empty?()

    no_labelled_link =
      page
      |> LazyHTML.query("a")
      |> Enum.all?(fn element ->
        not String.contains?(LazyHTML.text(element), label) and
          not Enum.any?(LazyHTML.attribute(element, "aria-label"), &String.contains?(&1, label))
      end)

    no_path_link and no_labelled_link
  end

  def behaviour_outcome?(context, :second_session_message, [message]),
    do: has_element?(context.second_view, "[data-role=user-message]", message)

  def behaviour_outcome?(context, :second_session_response, _args) do
    context.second_view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-role=assistant-message][data-streaming=false]")
    |> Enum.count()
    |> Kernel.==(1)
  end

  def behaviour_outcome?(context, :runner_reported, [alert]),
    do: alert_visible?(context, alert)

  def behaviour_outcome?(context, :stored_transcript_unchanged, _args),
    do: CodexChat.load_transcript(context.user_id) == context.transcript_before

  def behaviour_outcome?(_context, :no_codex_session, _args) do
    not Enum.any?(codex_fixture_calls(), &match?({:open, _, _}, &1))
  end

  def behaviour_outcome?(_context, :generated_image_inline, [file]) do
    content = image_turn_content(file)

    html =
      ChatMarkdown.to_html(content, false, codex_images: true)
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()

    String.contains?(html, "/chat/generated-images/abcdef12-3456/#{file}") and
      String.contains?(html, "<img")
  end

  def behaviour_outcome?(_context, :family_reference_as_text, _args) do
    source = "![Generated image](codex-image:abcdef12-3456/exec-fixture-image.png)"

    html =
      ChatComponents.markdown_body_html(source,
        hard_breaks: true,
        attrs: %{"data-role": "family-chat-message-body", class: "family-chat-message-body"}
      )

    String.contains?(html, "[image not shown: Generated image]") and
      not String.contains?(html, "<img")
  end

  def behaviour_outcome?(context, :image_cached_and_sandboxed, _args) do
    Plug.Conn.get_resp_header(context.image_response, "cache-control") == ["private, max-age=60"] and
      Plug.Conn.get_resp_header(context.image_response, "content-security-policy") == [
        "default-src 'none'; sandbox"
      ]
  end

  def behaviour_outcome?(context, :image_echoes_no_header, _args) do
    values = Enum.map(context.image_response.resp_headers, &elem(&1, 1))
    not Enum.any?(values, &String.contains?(&1, context.image_request_path))
  end

  def behaviour_outcome?(_context, :repository_logo_present, _args) do
    match?(
      {:ok, _type, _bytes},
      CodexChat.repository_image("apps/bnest-app/priv/static/images/beaver-nest-logo.png")
    )
  end

  def behaviour_outcome?(context, :manifest_names_app, _args) do
    manifest = fetch_manifest(context)
    icon_sources = manifest["icons"] |> Enum.map(& &1["src"]) |> Enum.sort()

    manifest["name"] == "Beaver Nest" and manifest["short_name"] == "Beaver Nest" and
      manifest["display"] == "standalone" and manifest["start_url"] == "/" and
      icon_sources == Pwa.install_metadata().icon_paths |> Enum.sort()
  end

  def behaviour_outcome?(context, :manifest_icons_load, _args) do
    icons = Enum.map(fetch_manifest(context)["icons"], & &1["src"])
    length(icons) == 2 and Enum.all?(icons, &(get(context.conn, &1).status == 200))
  end

  def behaviour_outcome?(context, :worker_precaches_shell, [cache]) do
    body = context.service_worker_body

    String.contains?(body, ~s(CACHE_NAME = "#{cache}")) and
      String.contains?(body, ~s("/manifest.webmanifest")) and
      String.contains?(body, ~s("/assets/css/app.css")) and
      String.contains?(body, ~s("/assets/js/app.js")) and
      String.contains?(body, ~s("/images/beaver-nest-192.png")) and
      String.contains?(body, ~s("/images/beaver-nest-512.png")) and
      String.contains?(body, "cache.addAll(APP_SHELL)")
  end

  def behaviour_outcome?(context, :worker_never_precaches, [path]) do
    [shell] =
      Regex.run(~r/const APP_SHELL = \[(.*?)\];/s, context.service_worker_body,
        capture: :all_but_first
      )

    not String.contains?(shell, ~s("#{path}"))
  end

  def behaviour_outcome?(context, :worker_activate_deletes, _args) do
    body = context.service_worker_body

    String.contains?(body, ".filter((key) => key !== CACHE_NAME)") and
      String.contains?(body, "caches.delete(key)")
  end

  def behaviour_outcome?(context, :room_not_found_body, [body]) do
    context.page |> LazyHTML.text() |> String.trim() == body
  end

  def behaviour_outcome?(context, :room_reveals_no_name, _args) do
    not String.contains?(LazyHTML.text(context.page), "Ruang Keluarga")
  end

  def behaviour_outcome?(context, expected, args),
    do: IntegrationFamilyChatDriver.behaviour_outcome?(context, expected, args)

  defp storage_control_label(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("section[aria-label='Migration status'] button")
    |> LazyHTML.text()
    |> String.trim()
  end

  # The turn the runner's image event completes: the reference the transcript appends
  # for a valid session thread, rendered the way the Codex room renders it.
  @image_thread "abcdef12-3456"

  defp image_turn_content(file) do
    {:ok, submitted} =
      Transcript.new("gpt-6.1-terra", "medium")
      |> Transcript.submit("Generate an image without a reference")

    {:checkpoint, chat} =
      submitted
      |> Transcript.put_thread_id(@image_thread)
      |> then(fn sized -> CodexChat.apply_event(sized, {:image_generated, file}) end)

    chat.messages |> Enum.find(&(&1.role == :assistant)) |> Map.fetch!(:content)
  end

  defp fetch_manifest(context) do
    %{status: 200, resp_body: body} = get(context.conn, "/manifest.webmanifest")
    Jason.decode!(body)
  end

  # A linked install asset the endpoint serves to a visitor's request.
  defp served_path?(context, path), do: get(context.conn, path).status == 200

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
    {:ok, record} = Records.read(:chat, user_id)
    {:ok, conversations} = Conversations.restore(record["state"], DateTime.utc_now())

    {:ok, %{transcript: %{messages: []}}} =
      BnestApp.CodexChat.selected_conversation(conversations)

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

  # Every regular file the current instance stores, flat records and the SQLite database with its sidecars, read
  # whole. Either primary keeps its accounts in one of the two roots.
  defp instance_stored_bytes do
    paths = BnestApp.TestInstance.state().paths

    [paths.flat_instance_root, paths.sqlite_instance_root]
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*")))
    |> Enum.filter(&File.regular?/1)
    |> Enum.map_join(&File.read!/1)
  end

  defp pointer_bytes do
    case File.read(FileConfigStore.pointer_path()) do
      {:ok, bytes} -> bytes
      {:error, :enoent} -> :absent
    end
  end

  # Only the current instance's pointer is removed. The instance's drop restores the run base's pointer.
  defp remove_instance_pointer! do
    if BnestApp.TestInstance.state() == nil,
      do: raise("no test instance is current; refusing to remove a storage pointer")

    case File.rm(FileConfigStore.pointer_path()) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        raise "could not remove the instance storage pointer: #{inspect(reason)}"
    end
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

    # Submit the folder the check rendered back, as a browser does, not the typed spelling.
    context.view
    |> form("form[phx-submit=create_database]")
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

  # The artifact's own evidence, read through a separate read-only connection: its quick
  # check, its byte digest, and the logical proof over its migration versions and catalog,
  # computed as the backup proof defines it.
  defp independent_artifact_proof(path) do
    with true <- File.regular?(path),
         {:ok, connection} <- Exqlite.Sqlite3.open(path, mode: :readonly) do
      try do
        [[quick_check]] = sqlite_rows(connection, "PRAGMA quick_check")

        versions =
          connection
          |> sqlite_rows("SELECT version FROM schema_migrations ORDER BY version")
          |> Enum.map(&hd/1)

        catalog =
          sqlite_rows(
            connection,
            "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
          )

        logical =
          %{schema_versions: versions, schema: catalog}
          |> Jason.encode!()
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)

        {:ok,
         %{
           quick_check: quick_check,
           sha256: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower),
           schema_versions: versions,
           logical_sha256: logical
         }}
      after
        :ok = Exqlite.Sqlite3.close(connection)
      end
    else
      _unreadable -> {:error, :unreadable}
    end
  end

  defp sqlite_rows(connection, sql) do
    {:ok, statement} = Exqlite.Sqlite3.prepare(connection, sql)
    {:ok, rows} = Exqlite.Sqlite3.fetch_all(connection, statement)
    :ok = Exqlite.Sqlite3.release(connection, statement)
    rows
  end

  # Opens home as the visitor and follows the entry link `role` names to its page.
  defp follow_home_entry(conn, role) do
    home = get(conn, "/")

    [href] =
      home.resp_body
      |> LazyHTML.from_document()
      |> LazyHTML.query("[data-role=#{role}]")
      |> LazyHTML.attribute("href")

    get(conn, href)
  end

  # A record read of the visitor's own session, account or theme, which the browser pipeline
  # makes for every request.
  defp visitor_own_read?({_module, :read, arguments}, owner, token) do
    case Enum.drop_while(arguments, &(&1 not in [:session, :account, :theme])) do
      [:session, digest | _server] -> digest == BnestApp.Identity.session_digest(token)
      [type, ^owner | _server] when type in [:account, :theme] -> true
      _other -> false
    end
  end

  defp visitor_own_read?(_access, _owner, _token), do: false

  # A redirect to the login page that returns the visitor to `route` afterwards.
  defp login_redirect_returning_to?(%{status: 302} = response, route) do
    target = URI.parse(redirected_to(response))
    target.path == "/login" and URI.decode_query(target.query || "")["return_to"] == route
  end

  defp login_redirect_returning_to?(_response, _route), do: false

  # Pins the identity cutover flag for the scenario and restores it after.
  defp pin_cutover(context, enabled) do
    previous = Application.fetch_env!(:bnest_app, :identity_cutover_enabled)
    Application.put_env(:bnest_app, :identity_cutover_enabled, enabled)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, :identity_cutover_enabled, previous)
    end)

    context
  end

  # The outline spells an empty return path "(empty)", as the corpus does for
  # other empty values.
  defp login_return_path("(empty)"), do: ""
  defp login_return_path(return_to), do: return_to

  # One setup form submission per rule the outline names, each seeded with the
  # scenario's own synthetic password.
  defp setup_case_params("no admin") do
    password = BnestApp.FreshDatabaseCase.account_password()

    %{
      "confirm" => "closed",
      "accounts" => %{
        "0" => setup_account_params("test-user-setup-one", password, password, ["children"]),
        "1" => setup_account_params("test-user-setup-two", password, password, ["parents"])
      }
    }
  end

  defp setup_case_params("duplicate username") do
    password = BnestApp.FreshDatabaseCase.account_password()

    %{
      "confirm" => "closed",
      "accounts" => %{
        "0" => setup_account_params("Test-User-Setup", password, password, ["admin"]),
        "1" => setup_account_params("test-user-setup", password, password, ["admin"])
      }
    }
  end

  defp setup_case_params("empty username") do
    password = BnestApp.FreshDatabaseCase.account_password()

    %{
      "confirm" => "closed",
      "accounts" => %{
        "0" => setup_account_params("", password, password, ["admin"])
      }
    }
  end

  defp setup_case_params("long username") do
    password = BnestApp.FreshDatabaseCase.account_password()

    %{
      "confirm" => "closed",
      "accounts" => %{
        "0" => setup_account_params(String.duplicate("a", 33), password, password, ["admin"])
      }
    }
  end

  defp setup_case_params("password mismatch") do
    password = BnestApp.FreshDatabaseCase.account_password()

    %{
      "confirm" => "closed",
      "accounts" => %{
        "0" =>
          setup_account_params("test-user-setup-one", password, "A different password 0!", [
            "admin"
          ])
      }
    }
  end

  defp setup_case_params("unchecked box") do
    password = BnestApp.FreshDatabaseCase.account_password()

    %{
      "accounts" => %{
        "0" => setup_account_params("test-user-setup-one", password, password, ["admin"])
      }
    }
  end

  defp setup_account_params(username, password, confirmation, roles) do
    %{
      "username" => username,
      "password" => password,
      "password_confirmation" => confirmation,
      "roles" => Map.new(roles, &{&1, "true"})
    }
  end

  # A role checkbox the refused setup re-renders ticked for the card.
  defp role_checked?(body, index, role) do
    Regex.match?(~r/name="accounts\[#{index}\]\[roles\]\[#{role}\]".*?checked/s, body)
  end

  # Whether a traced record call names `owner` as an identity or an owned identity's owner.
  defp names_owner?({_module, _operation, arguments}, owner),
    do: Enum.any?(arguments, &(&1 == owner or match?({^owner, _key}, &1)))

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

  # Points the storage profile at the marked run, so the default database directory is the
  # run's own SQLite directory for the rest of the test.
  defp use_runtime_storage_profile!(runtime) do
    previous = Application.fetch_env!(:bnest_app, :storage_profile)
    Application.put_env(:bnest_app, :storage_profile, {:test, runtime.run_id})

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, :storage_profile, previous)
    end)

    unless Storage.default_directory() == runtime.sqlite_path,
      do: raise("the storage profile does not resolve the marked run")
  end

  defp sqlite_schema_state do
    objects =
      SqliteRepo.query!("SELECT type, name, sql FROM sqlite_master ORDER BY type, name").rows

    %{
      objects: objects,
      indexes: for(["index", name, sql] <- objects, is_binary(sql), into: MapSet.new(), do: name),
      versions:
        SqliteRepo.query!("SELECT version FROM schema_migrations ORDER BY version").rows
        |> List.flatten(),
      runs: SqliteRepo.query!("SELECT migration_id, ddl_checksum FROM bnest_migration_runs").rows
    }
  end

  defp migration_item_rows(path),
    do:
      SqliteRepo.query!(
        "SELECT * FROM bnest_migration_items WHERE migration_id = ? AND source_relative_path = ?",
        [FlatMigration.migration_id(), path]
      ).rows

  defp migration_item_outcomes(path, column \\ "outcome"),
    do:
      SqliteRepo.query!(
        "SELECT source_relative_path, #{column} FROM bnest_migration_items WHERE migration_id = ? AND source_relative_path = ?",
        [FlatMigration.migration_id(), path]
      ).rows

  defp migrated_record_rows(path) do
    {:ok, {:record, classification}} = FlatMigration.classify_source(path)

    SqliteRepo.query!(
      "SELECT * FROM bnest_records WHERE record_type = ? AND record_key = ?",
      [classification.record_type, classification.record_key]
    ).rows
  end

  defp flat_tree_digests(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Map.new(fn path ->
      {Path.relative_to(path, root),
       :sha256 |> :crypto.hash(File.read!(path)) |> Base.encode16(case: :lower)}
    end)
  end

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

    {_output, 0} =
      System.cmd("git", ["init", "--quiet", repository],
        env: TestBackupDestination.git_child_env()
      )

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

  # BN-ADMIN-06: each outline kind becomes a folder the run owns: the live database's
  # own directory for the overlap refusal, a fresh symlink for the link refusal,
  # and a relative path for the remaining refusal.
  defp backup_folder_for!("inside the live database location") do
    Path.join(Path.dirname(Storage.database_path()), "backups")
  end

  defp backup_folder_for!("a symbolic link") do
    root =
      Path.join(System.tmp_dir!(), "bnest-backup-link-#{System.unique_integer([:positive])}")

    target =
      Path.join(System.tmp_dir!(), "bnest-backup-target-#{System.unique_integer([:positive])}")

    File.mkdir_p!(target)
    File.rm_rf(root)
    File.ln_s!(target, root)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(root) end)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(target) end)
    Path.join(root, "backups")
  end

  defp backup_folder_for!(_other), do: "relative/backup"

  defp manifest_path(import_id, store),
    do: Path.join(store.root, "system/manifests/#{import_id}.json")

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

  defp reconcile_task, do: Reconcile.execute([])

  # The routed schedules page as a connected administrator opens it: the first render
  # `live/2` returns (the dead-render document, which states checking), then the render once
  # the check the connected mount started has reported.
  defp open_label_view(context) do
    {:ok, view, first} = live(context.conn, @schedules_route)
    settled = render_async(view, IntegrityLabel.settle_ms())

    Map.merge(context, %{
      schedules_view: view,
      label_first: LazyHTML.from_fragment(first),
      label_page: LazyHTML.from_fragment(settled)
    })
  end

  defp note_viewport(context, [width, height]), do: Map.put(context, :viewport, {width, height})
  defp note_viewport(context, []), do: context

  defp label_form_event("daily"), do: "save_schedule"
  defp label_form_event("backup_folder"), do: "save_backup"

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

  # Waits for every task the Scheduler's task supervisor is running to finish.
  defp await_scheduler_tasks do
    BnestApp.Scheduler.Tasks
    |> Task.Supervisor.children()
    |> Enum.each(fn pid ->
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        30_000 -> raise "a queued scheduler task did not finish"
      end
    end)
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

defmodule BnestApp.Behaviour.FailingProgressStore do
  @moduledoc false

  @behaviour BnestApp.SifatAllah.Ports.ProgressStore

  @impl true
  def new, do: %{adapter: __MODULE__}

  @impl true
  def read(_store, _owner_id), do: {:error, :missing}

  @impl true
  def write(_store, _owner_id, _expected_revision, _record), do: {:error, :write_failed}
end
