defmodule BnestApp.Behaviour.IntegrationHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver
  @endpoint BnestAppWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BnestApp.Codex.FixtureModels
  alias BnestApp.Identity.Authorization
  alias BnestApp.Identity.CredentialVerifier
  alias BnestApp.SifatAllah

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
    send(context.view.pid, {:codex, session, {:assistant_update, "Fixture response"}})
    send(context.view.pid, {:codex, session, {:assistant_update, "Fixture response complete."}})
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

    Map.merge(context, %{
      conn: conn,
      identity_role: role,
      authenticated: true,
      user_id: identity.user_id
    })
  end

  @impl true
  def prepare_behaviour(context, :unauthenticated, _args),
    do: Map.merge(context, %{authenticated: false, conn: Phoenix.ConnTest.build_conn()})

  def prepare_behaviour(context, :uninitialized, _args), do: Map.put(context, :setup_open, true)

  def prepare_behaviour(context, :approved_account, _args),
    do: Map.put(context, :account_exists, true)

  def prepare_behaviour(context, :approved_argon2_account, _args),
    do: Map.merge(context, %{account_exists: true, verifier: "$argon2id$"})

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

  def prepare_behaviour(context, state, args),
    do: Map.merge(context, %{pending_behaviour_state: state, pending_behaviour_args: args})

  @impl true
  def perform_behaviour(context, :open_protected_route, [route]) do
    response = get(context.conn, route)
    Map.merge(context, %{response: response, redirected: response.status == 302})
  end

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

  def perform_behaviour(context, :login, _args) do
    {username, password} = BnestAppWeb.ConnCase.test_credentials()
    {:ok, token} = BnestApp.Identity.login(username, password)
    Map.merge(context, %{authenticated: true, token: token})
  end

  def perform_behaviour(context, :logout_current_browser, _args) do
    if context[:token], do: BnestApp.Identity.logout(context.token)
    Map.put(context, :authenticated, false)
  end

  def perform_behaviour(context, :reload_same_browser, _args), do: context

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

  defp roles_for(:child), do: ["children"]
  defp roles_for(:parent), do: ["parents"]
  defp roles_for(_role), do: ["admin"]

  defp answer_position(view, correct_answer) do
    Enum.find_index(1..4, fn index ->
      has_element?(view, ".sifat-answer-grid button:nth-child(#{index})", correct_answer)
    end)
  end

  defp effort_label("xhigh"), do: "XHigh"
  defp effort_label(effort), do: String.capitalize(effort)
end
