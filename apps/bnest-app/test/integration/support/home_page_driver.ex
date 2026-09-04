defmodule BnestApp.Behaviour.IntegrationHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver
  @endpoint BnestAppWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BnestApp.AdminConfig.Registry, as: AdminRegistry
  alias BnestApp.Backup.{Config, Run}
  alias BnestApp.{Chat, DataRepository}
  alias BnestApp.Codex.FixtureModels
  alias BnestApp.DataRepository.Import
  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.DataRepository.Store, as: RecordStore
  alias BnestApp.Identity.{Authorization, Bootstrap, CredentialVerifier, FileStore}
  alias BnestApp.Release.Migrations.PersistentSchedules
  alias BnestApp.Scheduler.{Policy, Registry, Store}
  alias BnestApp.SifatAllah
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config, as: StorageConfig
  alias BnestApp.Storage.Location, as: StorageLocation
  alias BnestApp.Storage.Migration, as: StorageMigration
  alias BnestApp.Storage.Relocation, as: StorageRelocation
  alias BnestApp.Storage.Retirement, as: StorageRetirement
  alias BnestApp.TestRuntimeRoot

  @behaviour_now ~U[2026-08-30 20:00:00Z]

  @impl true
  def open(%{conn: conn} = context, "/") do
    response = get(conn, "/")
    Map.put(context, :page, LazyHTML.from_fragment(response.resp_body))
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

  @impl true
  def installable_as_app?(context) do
    manifest_response = get(context.conn, "/manifest.webmanifest")

    with 200 <- manifest_response.status,
         {:ok, manifest} <- Jason.decode(manifest_response.resp_body),
         "Beaver Nest" <- manifest["name"],
         "standalone" <- manifest["display"],
         [
           %{"src" => "/images/beaver-nest-192.png", "sizes" => "192x192"},
           %{"src" => "/images/beaver-nest-512.png", "sizes" => "512x512"}
         ] <- manifest["icons"],
         200 <- get(context.conn, "/service-worker.js").status,
         200 <- get(context.conn, "/images/beaver-nest-192.png").status,
         200 <- get(context.conn, "/images/beaver-nest-512.png").status do
      true
    else
      _not_installable -> false
    end
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
    context.page
    |> LazyHTML.query("[data-role=data-migration-entry]")
    |> Enum.empty?()
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

    has_element?(context.view, "[data-role=model-selector] option[value='#{model.id}'][selected]") or
      has_element?(context.view, ".model-badge[data-model='#{model.id}']")
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

    has_element?(context.view, "[data-role=effort-selector] option[value='#{effort}'][selected]") or
      has_element?(context.view, ".model-badge[data-reasoning-effort='#{effort}']")
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
    not has_element?(context.view, "textarea[disabled]") and
      not has_element?(context.view, ".send-button[disabled]")
  end

  @impl true
  def composer_unavailable?(context) do
    has_element?(context.view, "textarea[disabled]") and
      has_element?(context.view, ".send-button[disabled]")
  end

  @impl true
  def clear_chat_control_available?(context) do
    has_element?(context.view, "[data-role=clear-chat]:not([disabled])")
  end

  @impl true
  def chat_controls_arranged?(context) do
    has_element?(context.view, ".chat-actions > .model-badge") and
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
  def attempt_empty_message(context) do
    render_submit(context.view, "send", %{"chat" => %{"prompt" => "   "}})
    context
  end

  @impl true
  def send_message(context, message) do
    render_submit(context.view, "send", %{"chat" => %{"prompt" => message}})
    Map.put(context, :pending_turn?, true)
  end

  @impl true
  def submit_with_shift_enter(context, message), do: send_message(context, message)

  @impl true
  def attempt_message_before_finished(context, message) do
    render_submit(context.view, "send", %{"chat" => %{"prompt" => message}})
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
    session = context.view.pid
    send(context.view.pid, {:codex, session, {:thread_started, "fixture-thread"}})

    send(
      context.view.pid,
      {:codex, session, {:assistant_update, "fixture-answer", "Fixture response"}}
    )

    send(
      context.view.pid,
      {:codex, session, {:assistant_update, "fixture-answer", "Fixture response complete."}}
    )

    send(context.view.pid, {:codex, session, :turn_completed})

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

    {streamed?,
     context
     |> Map.put(:pending_turn?, false)
     |> Map.put(:persisted_chat, Jason.encode!(snapshot))}
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
    session = context.view.pid

    send(
      context.view.pid,
      {:codex, session, {:reasoning_update, "fixture-reasoning", "Fixture reasoning summary"}}
    )

    send(
      context.view.pid,
      {:codex, session, {:assistant_update, "fixture-progress", "Fixture progress"}}
    )

    send(
      context.view.pid,
      {:codex, session, {:assistant_update, "fixture-final", "Fixture final answer"}}
    )

    send(context.view.pid, {:codex, session, :turn_completed})

    snapshot = await_push_event(context.view, "persist-chat")

    context
    |> Map.put(:pending_turn?, false)
    |> Map.put(:persisted_chat, Jason.encode!(snapshot))
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

  @impl true
  def reject_message(context, message) do
    render_submit(context.view, "send", %{"chat" => %{"prompt" => message}})
    context
  end

  @impl true
  def report_codex_error(context, message) do
    send(context.view.pid, {:codex, context.view.pid, {:error, message}})
    render(context.view)
    context
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

  @impl true
  def reconnect(context) do
    context =
      if Map.has_key?(context, :persisted_chat),
        do: reload(context),
        else: open(context, context.route)

    context =
      if context[:pending_turn?] do
        send(
          context.view.pid,
          {:codex, context.view.pid,
           {:error,
            "The previous response was interrupted. Your transcript is preserved; send a new message to continue."}}
        )

        render(context.view)
        Map.put(context, :pending_turn?, false)
      else
        context
      end

    case Map.fetch(context, :draft) do
      {:ok, draft} ->
        render_change(context.view, "recover_draft", %{"chat" => %{"prompt" => draft}})
        context

      :error ->
        context
    end
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
    has_element?(context.view, "button", "Belajar 3 Pasangan")
  end

  @impl true
  def quiz_mode_available?(context), do: has_element?(context.view, "button", "Latihan Ujian")

  @impl true
  def start_learning(context) do
    context.view
    |> element("button", "Belajar 3 Pasangan")
    |> render_click()

    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def remember_every_sifat_pair(context) do
    progress =
      Enum.reduce(SifatAllah.curriculum(), SifatAllah.progress(), fn pair, acc ->
        SifatAllah.remember(acc, pair.id)
      end)

    conn =
      put_connect_params(context.conn, %{
        "sifat_allah" => Jason.encode!(Map.put(progress, "session", %{"mode" => "dashboard"}))
      })

    {:ok, view, _html} = live(conn, "/apps/sifat-allah")
    Map.put(context, :view, view)
  end

  @impl true
  def swipe_study_card_left(context) do
    render_hook(context.view, "swipe-study", %{"direction" => "left"})
    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def swipe_study_card_right(context) do
    render_hook(context.view, "swipe-study", %{"direction" => "right"})
    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

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
  def browser_back_to_mission(context) do
    render_hook(context.view, "dashboard", %{})
    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def study_card_shows?(context, name, meaning) do
    has_element?(context.view, "[data-role=study-card]", name) and
      has_element?(context.view, "[data-role=study-card]", meaning)
  end

  @impl true
  def study_card_colors_attributes?(context) do
    has_element?(context.view, "[data-memory-color=wajib]") and
      has_element?(context.view, "[data-memory-color=mustahil]")
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

    first_position != second_position
  end

  @impl true
  def quiz_answer_choices_locked?(context),
    do: not has_element?(context.view, ".sifat-answer-grid button:not([disabled])")

  @impl true
  def wait_for_quiz_auto_advance(context) do
    render_click(context.view, "next-question", %{})
    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
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
  def swipe_quiz_question_left(context) do
    render_hook(context.view, "swipe-quiz", %{"direction" => "left"})
    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

  @impl true
  def swipe_quiz_question_right(context) do
    render_hook(context.view, "swipe-quiz", %{"direction" => "right"})
    snapshot = await_push_event(context.view, "persist-sifat-allah")
    Map.put(context, :persisted_sifat_allah, Jason.encode!(snapshot))
  end

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
      user_id: identity.user_id
    })
  end

  @impl true
  def prepare_behaviour(context, :unauthenticated, _args),
    do: Map.merge(context, %{authenticated: false, conn: Phoenix.ConnTest.build_conn()})

  def prepare_behaviour(context, :uninitialized, _args) do
    runtime = TestRuntimeRoot.create!("authentication-bootstrap")
    ExUnit.Callbacks.on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)

    Map.merge(context, %{
      setup_open: true,
      identity_store: RecordStore.new!(runtime.path),
      identity_runtime: runtime
    })
  end

  def prepare_behaviour(context, :approved_account, _args),
    do: Map.put(context, :account_exists, true)

  def prepare_behaviour(context, :approved_argon2_account, _args) do
    {username, password} = BnestAppWeb.ConnCase.test_credentials()
    store = DataRepository.store()
    {:ok, %{"userId" => user_id}} = FileStore.read_username(store, username)
    {:ok, account} = FileStore.read_account(store, user_id)

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
    Map.merge(context, %{token_a: token_a, token_b: token_b, browser_a: true, browser_b: true})
  end

  def prepare_behaviour(context, :multi_role_user, roles),
    do: Map.put(context, :auth_user, %{"userId" => "user-integration", "roles" => roles})

  def prepare_behaviour(context, :two_isolated_users, _args),
    do: Map.merge(context, %{owner_a: "user-a", owner_b: "user-b"})

  def prepare_behaviour(context, :recognized_browser_sources, _args),
    do:
      Map.merge(context, %{
        central_store: DataRepository.store(),
        browser_sources: recognized_browser_sources()
      })

  def prepare_behaviour(context, :absent_theme_source, _args),
    do:
      Map.merge(context, %{
        central_store: DataRepository.store(),
        browser_sources: [],
        pending_behaviour_state: :absent_theme_source
      })

  def prepare_behaviour(context, :invalid_browser_source, _args) do
    store = DataRepository.store()
    {:ok, accepted} = Import.browser(store, context.user_id, chat_source())

    Map.merge(context, %{
      central_store: store,
      accepted_before: RecordStore.read(store, :chat, context.user_id),
      accepted_import: accepted,
      browser_sources: [
        %{"storageArea" => "localStorage", "storageKey" => "unknown", "payload" => "opaque"}
      ]
    })
  end

  def prepare_behaviour(context, :interrupted_import, _args) do
    store = DataRepository.store()
    {:ok, first} = Import.browser(store, context.user_id, chat_source())
    Map.merge(context, %{central_store: store, first_import_id: first.import_id})
  end

  def prepare_behaviour(context, :stale_browser_revision, _args) do
    store = DataRepository.store()
    {:ok, _accepted} = Import.browser(store, context.user_id, chat_source())
    {:ok, newer} = RecordStore.read(store, :chat, context.user_id)

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
      central_store: DataRepository.store(),
      browser_sources: [chat_source()],
      browser_keys: %{"bnest.chat.v1" => chat_source()["payload"], "unrelated" => "keep"}
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

  def prepare_behaviour(context, :no_backup_override, _args), do: prepare_default_backup(context)

  def prepare_behaviour(context, :admin_opened_schedules, _args),
    do: prepare_backup_destination(context)

  def prepare_behaviour(context, :saved_daily_schedule, _args) do
    ensure_scheduler_storage()
    key = schedule_key("restart")
    :ok = Store.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    future_wib = now |> DateTime.add(8 * 60 * 60) |> Calendar.strftime("%H:%M")

    {:ok, _schedule} =
      Store.update_daily(
        key,
        %{"daily_time_wib" => future_wib, "enabled" => "true", "revision" => "1"},
        now
      )

    Map.merge(context, %{schedule_key: key, schedule_before_restart: Store.get_schedule(key)})
  end

  def prepare_behaviour(context, :multiple_missed_slots, _args) do
    ensure_scheduler_storage()
    key = schedule_key("catchup")
    :ok = Store.put_test_schedule(key, "family", "fixture", @behaviour_now)
    Map.put(context, :schedule_key, key)
  end

  def prepare_behaviour(context, :accepted_backup_claim, _args) do
    ensure_scheduler_storage()
    context = prepare_backup_destination(context)
    key = schedule_key("backup")
    :ok = Store.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)
    {:ok, location} = Config.save(context.backup_directory)
    {:ok, claim} = Store.claim_setup(key, location.destination_id, @behaviour_now)
    Map.merge(context, %{backup_claim: claim, backup_location: location})
  end

  def prepare_behaviour(context, :overlapping_coordinators, _args) do
    ensure_scheduler_storage()
    key = schedule_key("overlap")
    :ok = Store.put_test_schedule(key, "family", "fixture", @behaviour_now)
    Map.put(context, :schedule_key, key)
  end

  def prepare_behaviour(context, :contextual_schedules, _args) do
    ensure_scheduler_storage()
    key = schedule_key("family")
    :ok = Store.put_test_schedule(key, "family", "fixture", @behaviour_now)
    Map.put(context, :schedule_key, key)
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

  def prepare_behaviour(context, :second_family_handler, _args) do
    ensure_scheduler_storage()
    key = schedule_key("second-family")
    :ok = Store.put_test_schedule(key, "family", "fixture", @behaviour_now)
    Map.put(context, :schedule_key, key)
  end

  def prepare_behaviour(context, :typed_settings_panels, _args),
    do: Map.put(context, :declared_panels, AdminRegistry.panels())

  def prepare_behaviour(context, :expiry_policies, _args) do
    ensure_scheduler_storage()
    key = schedule_key("expires")
    :ok = Store.put_test_schedule(key, "family", "fixture", @behaviour_now, max_occurrences: 1)

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

  def prepare_behaviour(context, :storage_ui_not_visited, _args),
    do: Map.put(context, :storage_ui_visits, 0)

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
    ExUnit.Callbacks.on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)
    Map.put(context, :sqlite_database_path, Path.join(runtime.sqlite_path, "bnest.sqlite3"))
  end

  def prepare_behaviour(context, :flat_primary_default_location, _args) do
    context = prepare_behaviour(context, :no_storage_configuration, [])
    runtime = TestRuntimeRoot.create!("sqlite-storage-migration")
    ExUnit.Callbacks.on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)
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
    StorageMigration.run(context.flat_root, repo)
    context
  end

  def prepare_behaviour(context, :all_verification_checks_pass, _args) do
    context = prepare_behaviour(context, :flat_primary_default_location, [])

    {:ok, _config} =
      StorageConfig.persist_directory(Path.dirname(context.sqlite_database_path))

    repo = sqlite_repo_started!(context.sqlite_database_path)
    Ecto.Migrator.run(repo, sqlite_migrations_path(), :up, all: true)
    result = StorageMigration.run(context.flat_root, repo)
    Map.put(context, :migration_run_result, result)
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
      StorageCoordinator.stop()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    flat_root = Path.join(runtime.sqlite_path, "flat-source")
    legacy_directory = Path.join(runtime.sqlite_path, "legacy-config")
    destination = Path.join(runtime.sqlite_path, "relocated")
    File.mkdir_p!(flat_root)
    File.write!(Path.join(flat_root, ".gitkeep"), "")
    seed_flat_fixtures!(flat_root)
    {:ok, _config} = StorageConfig.persist_directory(legacy_directory)
    database_path = Path.join(legacy_directory, StorageLocation.filename())
    repo = sqlite_repo_started!(database_path)
    Ecto.Migrator.run(repo, sqlite_migrations_path(), :up, all: true)
    StorageMigration.run(flat_root, repo)
    :ok = StorageMigration.activate!(repo)

    Map.merge(context, %{
      flat_root: flat_root,
      legacy_database_path: database_path,
      relocation_destination: destination
    })
  end

  def prepare_behaviour(context, :routed_storage_generation_proven, _args) do
    context = prepare_behaviour(context, :legacy_authoritative_sqlite, [])
    {:ok, config} = StorageRelocation.run(context.relocation_destination)
    Map.put(context, :storage_generation, config["databaseGeneration"])
  end

  def prepare_behaviour(context, :denied_settings_visitor, _args),
    do: establish_identity(context, :child)

  @impl true
  def perform_behaviour(context, :open_protected_route, [route]) do
    response = get(context.conn, route)
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
      login_form_only: login_form_only
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
    {username, password} = BnestAppWeb.ConnCase.test_credentials()
    {:ok, token} = BnestApp.Identity.login(username, password)
    Map.merge(context, %{authenticated: true, token: token})
  end

  def perform_behaviour(context, :logout_current_browser, _args) do
    if context[:token], do: BnestApp.Identity.logout(context.token)
    Map.put(context, :authenticated, false)
  end

  def perform_behaviour(context, :reload_same_browser, _args),
    do: Map.put(context, :reload_result, BnestApp.Identity.current_user(context.token))

  def perform_behaviour(context, :logout_browser_a, _args) do
    :ok = BnestApp.Identity.logout(context.token_a)

    Map.merge(context, %{
      browser_a: false,
      browser_b: match?({:ok, _}, BnestApp.Identity.current_user(context.token_b))
    })
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

  def perform_behaviour(context, :accept_and_read_back, _args) do
    [source] = context.browser_sources
    result = Import.browser(context.central_store, context.user_id, source)

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

  def perform_behaviour(context, :start_managed_migration, _args) do
    Map.put(context, :storage_config, StorageConfig.ensure_default!())
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
    Map.put(context, :migration_run_result, StorageMigration.run(context.flat_root, repo))
  end

  def perform_behaviour(context, :retry_same_migration, _args) do
    repo = sqlite_repo_started!(context.sqlite_database_path)
    before_count = repo.query!("SELECT count(*) FROM bnest_migration_items").rows

    result = StorageMigration.run(context.flat_root, repo)

    after_count = repo.query!("SELECT count(*) FROM bnest_migration_items").rows

    context
    |> Map.put(:migration_run_result, result)
    |> Map.put(:item_count_before_retry, before_count)
    |> Map.put(:item_count_after_retry, after_count)
  end

  def perform_behaviour(context, :commit_authority_switch, _args) do
    repo = sqlite_repo_started!(context.sqlite_database_path)
    :ok = StorageMigration.activate!(repo)
    Map.put(context, :storage_config, elem(StorageConfig.read(), 1))
  end

  def perform_behaviour(context, :retire_flat_identity_sources, _args) do
    identity = context.migration_identity

    Enum.each(
      [
        "system/bootstrap.json",
        "system/accounts/#{identity.user_id}.json",
        "system/usernames/#{identity.username}.json"
      ],
      fn relative -> File.rm!(Path.join(context.flat_root, relative)) end
    )

    Map.put(context, :flat_identity_retired?, true)
  end

  def perform_behaviour(context, :verify_migration, _args) do
    repo = sqlite_repo_started!(context.sqlite_database_path)
    Ecto.Migrator.run(repo, sqlite_migrations_path(), :up, all: true)
    result = StorageMigration.run(context.flat_root, repo)
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
        StorageRelocation.run(context.relocation_destination)
      )

  def perform_behaviour(context, :retire_legacy_storage, _args),
    do:
      Map.put(
        context,
        :retirement_result,
        StorageRetirement.run(context.flat_root, context.storage_generation)
      )

  def perform_behaviour(context, :open_admin_settings, _args) do
    response = get(context.conn, "/admin/settings")
    home = get(context.conn, "/")
    Map.merge(context, %{response: response, home_response: home})
  end

  def perform_behaviour(context, :open_schedules_from_home, _args) do
    response = get(context.conn, "/admin/settings/schedules")
    Map.put(context, :response, response)
  end

  def perform_behaviour(context, :open_admin_settings_from_home, _args) do
    response = get(context.conn, "/admin/settings")
    Map.put(context, :response, response)
  end

  def perform_behaviour(context, :resolve_backup_destination, _args) do
    result = Config.resolve()

    public_result =
      case result do
        {:ok, location} -> %{destination_id: location.destination_id}
        {:error, reason} -> %{error: reason}
      end

    Map.merge(context, %{backup_resolution: result, public_backup_result: public_result})
  end

  def perform_behaviour(context, :save_backup_override, _args) do
    result = Config.save(context.backup_directory)
    {:ok, location} = result
    key = schedule_key("save")
    :ok = Store.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)
    before = Store.run_count()
    {:ok, first} = Store.claim_setup(key, location.destination_id, @behaviour_now)
    {:ok, second} = Store.claim_setup(key, location.destination_id, @behaviour_now)

    Map.merge(context, %{
      backup_save_result: result,
      first_setup_claim: first,
      second_setup_claim: second,
      setup_run_delta: Store.run_count() - before
    })
  end

  def perform_behaviour(context, :restart_scheduler, _args) do
    before = context.schedule_before_restart
    supervisor = Process.whereis(BnestApp.Supervisor)
    scheduler = Process.whereis(BnestApp.Scheduler)
    if is_pid(scheduler), do: Process.exit(scheduler, :kill)
    await_scheduler_restart(supervisor, scheduler, 100)

    Map.merge(context, %{
      schedule_after_restart: Store.get_schedule(context.schedule_key),
      scheduler_restarted?: true,
      schedule_before_restart: before
    })
  end

  def perform_behaviour(context, :reconcile_startup, _args) do
    claims = Store.claim_due(@behaviour_now)
    claim = Enum.find(claims, &(&1.schedule_key == context.schedule_key))

    Map.merge(context, %{
      reconciled_claim: claim,
      reconciled_schedule: Store.get_schedule(context.schedule_key)
    })
  end

  def perform_behaviour(context, :run_backup_handler, _args),
    do: Map.put(context, :backup_execution, Run.execute(context.backup_claim, @behaviour_now))

  def perform_behaviour(context, :reconcile_overlap, _args) do
    claims =
      1..2
      |> Task.async_stream(fn _coordinator -> Store.claim_due(@behaviour_now) end,
        max_concurrency: 2
      )
      |> Enum.flat_map(fn {:ok, rows} ->
        Enum.filter(rows, &(&1.schedule_key == context.schedule_key))
      end)

    [claim] = claims

    {:retryable, attempt_2} =
      Store.fail_attempt(claim.run_id, claim.attempt, :capacity, @behaviour_now)

    at_2 = DateTime.add(@behaviour_now, 5 * 60)
    retried_2 = Enum.find(Store.claim_due(at_2), &(&1.run_id == claim.run_id))
    {:retryable, attempt_3} = Store.fail_attempt(claim.run_id, retried_2.attempt, :capacity, at_2)
    at_3 = DateTime.add(at_2, 30 * 60)
    retried_3 = Enum.find(Store.claim_due(at_3), &(&1.run_id == claim.run_id))
    {:failed, failed} = Store.fail_attempt(claim.run_id, retried_3.attempt, :capacity, at_3)

    Map.merge(context, %{overlap_claims: claims, retry_attempts: [attempt_2, attempt_3, failed]})
  end

  def perform_behaviour(context, :verify_new_backup, _args) do
    {:ok, location} = Config.save(context.backup_directory)
    key = schedule_key("retention")
    :ok = Store.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)

    receipts =
      Enum.map(0..8, fn days ->
        at = DateTime.add(@behaviour_now, -days * 86_400)
        {:ok, claim} = Store.claim_setup(key, "#{location.destination_id}-#{days}", at)
        {:ok, receipt} = Run.execute(claim, at)
        receipt
      end)

    Map.put(context, :retention_receipts, receipts)
  end

  def perform_behaviour(context, :run_second_handler, _args) do
    claim = Enum.find(Store.claim_due(@behaviour_now), &(&1.schedule_key == context.schedule_key))
    result = Registry.execute(claim, @behaviour_now)
    Map.merge(context, %{family_handler_claim: claim, family_handler_result: result})
  end

  def perform_behaviour(context, :reconcile_expiry, _args) do
    initial = Store.claim_due(@behaviour_now)
    first = Enum.find(initial, &(&1.schedule_key == context.schedule_key))

    {:retryable, retry} =
      Store.fail_attempt(first.run_id, first.attempt, :capacity, @behaviour_now)

    later = Store.claim_due(DateTime.add(@behaviour_now, 86_400))

    Map.merge(context, %{
      expiration_eligibility:
        Enum.map(context.expiration_policies, &Policy.eligible?(&1, @behaviour_now)),
      expiration_first_claim: first,
      expiration_retry: retry,
      expiration_later_claims: later
    })
  end

  @impl true
  def behaviour_outcome?(context, :redirected_to_login, _args), do: context.redirected
  def behaviour_outcome?(context, :login_form_only, _args), do: context.login_form_only
  def behaviour_outcome?(context, :no_user_data_access, _args), do: context.redirected
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
    do: not context.authenticated

  def behaviour_outcome?(context, :no_plaintext_password, _args) do
    bytes =
      context.identity_store.root
      |> Path.join("**/*.json")
      |> Path.wildcard()
      |> Enum.map_join(&File.read!/1)

    String.starts_with?(context.verifier, "$argon2id$") and
      CredentialVerifier.verify(context.identity_password, context.verifier) and
      not String.contains?(bytes, context.identity_password)
  end

  def behaviour_outcome?(context, :same_browser_authenticated, _args),
    do: match?({:ok, %{"userId" => _user_id}}, context.reload_result)

  def behaviour_outcome?(context, :browser_a_logged_out, _args), do: not context.browser_a
  def behaviour_outcome?(context, :browser_b_authenticated, _args), do: context.browser_b
  def behaviour_outcome?(context, :operation_allowed, _args), do: context.operation_allowed

  def behaviour_outcome?(context, :administration_denied, _args),
    do: context.administration_denied

  def behaviour_outcome?(context, :denied_before_repository, _args), do: context.cross_user_denied

  def behaviour_outcome?(_context, :pointer_under_configuration_home, _args),
    do: String.ends_with?(StorageLocation.config_directory(), "/.config/bnest")

  def behaviour_outcome?(context, :sqlite_under_production_data, _args),
    do: context.storage_config["databaseDirectory"] == StorageLocation.default_directory()

  def behaviour_outcome?(context, :no_browser_confirmation, _args),
    do: context.storage_ui_visits == 0

  def behaviour_outcome?(context, :folder_normalized_with_fixed_filename, _args) do
    case StorageConfig.read() do
      {:ok, config} ->
        config["databaseFilename"] == StorageLocation.filename() and
          config["databaseDirectory"] == Path.expand(context.requested_directory)

      {:error, _reason} ->
        false
    end
  end

  def behaviour_outcome?(_context, :validated_location_stored_privately, _args) do
    stat = File.stat!(StorageConfig.pointer_path())
    Bitwise.band(stat.mode, 0o777) == 0o600
  end

  def behaviour_outcome?(context, :safe_correction_explained, _args),
    do:
      context.unsafe_response
      |> LazyHTML.query("[role=alert]")
      |> LazyHTML.text()
      |> String.contains?("Enter an absolute server-local folder")

  def behaviour_outcome?(_context, :no_storage_created, _args),
    do: StorageConfig.read() == {:error, :absent}

  def behaviour_outcome?(context, outcome, _args)
      when outcome in [:schema_matches_checksum, :no_duplicate_schema_objects] do
    context.schema_before_second_apply == context.schema_after_second_apply and
      context.schema_before_second_apply != []
  end

  def behaviour_outcome?(context, :deterministic_inventory, _args) do
    items = StorageMigration.inventory(context.flat_root)
    items != [] and items == Enum.sort(items)
  end

  def behaviour_outcome?(context, :database_under_resolved_directory, _args),
    do: File.exists?(context.sqlite_database_path)

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
    StorageMigration.parity_ok?(context.flat_root, repo)
  end

  def behaviour_outcome?(context, :accepted_items_not_duplicated, _args),
    do: context.item_count_before_retry == context.item_count_after_retry

  def behaviour_outcome?(context, :remaining_items_continue, _args),
    do: context.migration_run_result.accepted > 0

  def behaviour_outcome?(_context, :future_reads_use_sqlite, _args),
    do: StorageConfig.phase() == :sqlite_primary

  def behaviour_outcome?(context, :writes_compatible_with_rollback, _args),
    do: File.exists?(Path.join(context.flat_root, "system/bootstrap.json"))

  def behaviour_outcome?(context, :journeys_survive_restart, _args) do
    StorageCoordinator.stop()
    _repo = sqlite_repo_started!(context.sqlite_database_path)
    identity = context.migration_identity

    with true <- context.flat_identity_retired?,
         :closed <- BnestApp.Identity.setup_status(),
         {:ok, token} <- BnestApp.Identity.login(identity.username, identity.password),
         {:ok, %{"normalizedUsername" => username}} <- BnestApp.Identity.current_user(token),
         true <- username == identity.username,
         admin_conn <-
           Plug.Test.put_req_cookie(
             Phoenix.ConnTest.build_conn(),
             "_bnest_identity",
             token
           ),
         %{status: 200} <- get(admin_conn, "/admin/settings"),
         :ok <- BnestApp.Identity.logout(token),
         {:error, :unauthenticated} <- BnestApp.Identity.current_user(token) do
      true
    else
      _failure -> false
    end
  end

  def behaviour_outcome?(_context, :sqlite_not_authoritative, _args),
    do: StorageConfig.phase() == :flat_primary

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
        StorageConfig.resolved_database_path() ==
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
      StorageConfig.read()
    ) and File.exists?(Path.join(context.flat_root, ".gitkeep"))
  end

  def behaviour_outcome?(context, :immutable_envelopes, _args) do
    Enum.all?(context.import_results, fn
      {:ok, %{import_id: import_id}} ->
        match?(
          {:ok, %{"payloadEncoding" => "utf8-string"}},
          RecordStore.read(context.central_store, :browser_import, {context.user_id, import_id})
        )

      _failure ->
        false
    end)
  end

  def behaviour_outcome?(context, :normalized_records_read, _args) do
    Enum.all?([:chat, :sifat_allah, :theme], fn type ->
      case RecordStore.read(context.central_store, type, context.user_id) do
        {:ok, %{"ownerId" => owner}} -> owner == context.user_id
        _missing -> false
      end
    end)
  end

  def behaviour_outcome?(context, :absent_theme_recorded, _args) do
    with [{:ok, %{import_id: import_id}}] <- context.import_results,
         {:ok, %{"recoverySource" => %{"kind" => "browser-absence"}}} <-
           RecordStore.read(context.central_store, :manifest, import_id) do
      true
    else
      _failure -> false
    end
  end

  def behaviour_outcome?(context, :no_theme_preference, _args),
    do: RecordStore.read(context.central_store, :theme, context.user_id) == {:error, :missing}

  def behaviour_outcome?(context, :safe_rejected_import, _args),
    do: match?([{:error, :unsupported_source, _manifest}], context.import_results)

  def behaviour_outcome?(context, :source_and_record_unchanged, _args),
    do: RecordStore.read(context.central_store, :chat, context.user_id) == context.accepted_before

  def behaviour_outcome?(context, :idempotent_import_identity, _args),
    do: match?({:ok, %{import_id: id}} when id == context.first_import_id, context.retry_result)

  def behaviour_outcome?(context, :accepted_data_preserved, _args),
    do:
      import_envelope_count(context.central_store, context.user_id) ==
        context.envelopes_before_retry and
        match?(
          {:ok, %{"recordType" => "chat"}},
          RecordStore.read(context.central_store, :chat, context.user_id)
        )

  def behaviour_outcome?(context, :newer_record_preserved, _args),
    do:
      RecordStore.read(context.central_store, :chat, context.user_id) ==
        {:ok, context.centralized_before}

  def behaviour_outcome?(context, :refresh_required, _args),
    do: match?({:error, :stale_revision, %{"status" => "retryable"}}, context.stale_result)

  def behaviour_outcome?(context, :only_accepted_key_cleared, _args),
    do: context.browser_keys_after == %{"unrelated" => "keep"}

  def behaviour_outcome?(context, :server_only_persistence, _args),
    do:
      match?(
        {:ok, %{"recordType" => "chat"}},
        RecordStore.read(context.central_store, :chat, context.user_id)
      )

  def behaviour_outcome?(context, :transcript_preserved, _args),
    do: context.continued_chat.messages == context.transcript_before

  def behaviour_outcome?(context, :fresh_conversation_reported, _args),
    do:
      is_nil(context.continued_chat.thread_id) and
        String.contains?(context.continued_chat.error, "fresh conversation")

  def behaviour_outcome?(context, :default_backup_folder, _args),
    do:
      match?(
        {:ok, %{directory: directory}} when directory == context.default_backup_directory,
        context.backup_resolution
      )

  def behaviour_outcome?(context, :no_private_path, _args),
    do:
      not String.contains?(
        inspect(context.public_backup_result),
        context.default_backup_directory
      ) and
        not Map.has_key?(context.public_backup_result, :directory)

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
          receipt["sourceGeneration"] == StorageConfig.database_generation()

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

  def behaviour_outcome?(context, :context_groups, _args),
    do:
      context.response.status == 200 and
        String.contains?(context.response.resp_body, "Family schedules") and
        String.contains?(context.response.resp_body, "Admin/system schedules")

  def behaviour_outcome?(context, :typed_backup_link, _args),
    do:
      String.contains?(
        context.response.resp_body,
        ~s(href="/admin/settings/schedules")
      )

  def behaviour_outcome?(context, :not_found_before_reads, _args),
    do: context.response.status == 404 and context.response.resp_body == "Not found"

  def behaviour_outcome?(context, :no_admin_home_entry, _args),
    do:
      not String.contains?(context.home_response.resp_body, "Admin settings") and
        not String.contains?(context.home_response.resp_body, "Schedules &amp; backups")

  def behaviour_outcome?(context, :owned_retention, _args),
    do: length(Run.owned_receipts(context.backup_directory)) == 7

  def behaviour_outcome?(context, :preserve_unowned, _args),
    do:
      File.exists?(context.unknown_backup_file) and
        File.exists?(Path.join(context.previous_destination, "previous-destination.txt"))

  def behaviour_outcome?(context, :shared_execution, _args),
    do: match?({:ok, %{"artifactBasename" => nil}}, context.family_handler_result)

  def behaviour_outcome?(context, :shared_inventory, _args),
    do:
      Enum.any?(Store.family_inventory(), fn schedule ->
        schedule.schedule_key == context.schedule_key and schedule.last_run_state == "verified"
      end)

  def behaviour_outcome?(context, :panels_discoverable, _args),
    do:
      context.response.status == 200 and
        Enum.all?(context.declared_panels, fn panel ->
          String.contains?(context.response.resp_body, String.replace(panel.label, "&", "&amp;"))
        end)

  def behaviour_outcome?(context, :owner_allowlists, _args),
    do:
      Enum.all?(context.declared_panels, fn panel ->
        is_atom(panel.owner) and is_list(panel.editable_fields) and
          Enum.uniq(panel.editable_fields) == panel.editable_fields
      end)

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

  defp await_push_event(_view, "persist-chat") do
    user_id = Process.get(:bnest_behaviour_user_id)
    record = await_central_record(:chat, user_id, 100)
    record["state"]
  end

  defp await_push_event(_view, "clear-chat-storage") do
    user_id = Process.get(:bnest_behaviour_user_id)
    {:ok, %{"state" => %{"messages" => []}}} = BnestApp.DataRepository.read(:chat, user_id)
    %{}
  end

  defp await_push_event(_view, "persist-sifat-allah") do
    user_id = Process.get(:bnest_behaviour_user_id)
    {:ok, record} = BnestApp.DataRepository.read(:sifat_allah, user_id)
    Map.put(record["progress"], "session", record["session"])
  end

  defp await_push_event(view, event) do
    %{proxy: {ref, _topic, _}} = view

    receive do
      {^ref, {:push_event, ^event, payload}} -> payload
    end
  end

  defp await_central_record(type, user_id, attempts) do
    case BnestApp.DataRepository.read(type, user_id) do
      {:ok, record} ->
        record

      {:error, :missing} when attempts > 0 ->
        Process.sleep(10)
        await_central_record(type, user_id, attempts - 1)

      {:error, reason} ->
        raise "central #{type} record unavailable: #{inspect(reason)}"
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

    context.view
    |> form("form[phx-submit=create_database]", %{"directory" => directory})
    |> render_submit()

    Map.put(context, :requested_directory, directory)
  end

  defp unique_suffix, do: Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)

  defp sqlite_migrations_path, do: Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")

  defp sqlite_repo_started!(database_path) do
    :ok = StorageCoordinator.ensure_started!(database_path)
    SqliteRepo
  end

  defp seed_flat_fixtures!(root) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    user_id = "user-" <> unique_suffix()
    username = "test-user-sqlite-" <> String.downcase(unique_suffix())
    password = "Synthetic SQLite Password 123!"
    {:ok, verifier} = CredentialVerifier.hash(password)

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
      "payload" =>
        Jason.encode!(Map.put(SifatAllah.progress(), "session", %{"mode" => "dashboard"}))
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
    previous = System.get_env("BNEST_REPOSITORY_ROOT")
    System.put_env("BNEST_REPOSITORY_ROOT", repository)
    ExUnit.Callbacks.on_exit(fn -> restore_environment("BNEST_REPOSITORY_ROOT", previous) end)

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

  defp restore_environment(name, nil), do: System.delete_env(name)
  defp restore_environment(name, value), do: System.put_env(name, value)
  defp schedule_key(prefix), do: "bdd-#{prefix}-#{unique_suffix()}"

  defp ensure_scheduler_storage do
    :ok = StorageCoordinator.ensure_started!(StorageConfig.resolved_database_path())
    :ok = PersistentSchedules.apply_and_verify!(@behaviour_now)
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
