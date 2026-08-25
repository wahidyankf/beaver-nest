defmodule BnestApp.Behaviour.IntegrationHomePageDriver do
  @moduledoc false

  @behaviour BnestApp.Behaviour.Driver
  @endpoint BnestAppWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BnestApp.Codex.FixtureModels
  alias BnestApp.SifatAllah

  @impl true
  def open(%{conn: conn} = context, "/") do
    response = get(conn, "/")
    Map.put(context, :page, LazyHTML.from_fragment(response.resp_body))
  end

  def open(%{conn: conn} = context, route) do
    {:ok, view, _html} = live(conn, route)
    Map.put(context, :view, view)
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
    has_element?(context.view, "[data-role=model-selector] option[value='#{model.id}'][selected]")
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
    has_element?(
      context.view,
      "[data-role=effort-selector] option[value='#{String.downcase(effort)}'][selected]"
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
  def effort_selector_available?(context) do
    has_element?(context.view, "[data-role=effort-selector]:not([disabled])")
  end

  @impl true
  def effort_selector_unavailable?(context) do
    has_element?(context.view, "[data-role=effort-selector][disabled]")
  end

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
  def attempt_empty_message(context) do
    render_submit(context.view, "send", %{"chat" => %{"prompt" => "   "}})
    context
  end

  @impl true
  def send_message(context, message) do
    render_submit(context.view, "send", %{"chat" => %{"prompt" => message}})
    context
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

    {streamed?, Map.put(context, :persisted_chat, Jason.encode!(snapshot))}
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

  defp await_push_event(view, event) do
    %{proxy: {ref, _topic, _}} = view

    receive do
      {^ref, {:push_event, ^event, payload}} -> payload
    end
  end

  defp answer_position(view, correct_answer) do
    Enum.find_index(1..4, fn index ->
      has_element?(view, ".sifat-answer-grid button:nth-child(#{index})", correct_answer)
    end)
  end

  defp effort_label("xhigh"), do: "XHigh"
  defp effort_label(effort), do: String.capitalize(effort)
end
