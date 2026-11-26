defmodule BnestAppWeb.ChatConversationsLiveTest do
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.Test.CodexFixtureModels

  setup do
    previous = Application.fetch_env!(:bnest_app, :identity_cutover_enabled)
    Application.put_env(:bnest_app, :identity_cutover_enabled, false)
    on_exit(fn -> Application.put_env(:bnest_app, :identity_cutover_enabled, previous) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  test "a fresh chat shows a rail with one New chat conversation", %{conn: conn} do
    {conn, _identity} = scenario_authenticated_conn(conn, "chat-conv-fresh", ["admin"])
    {:ok, view, _html} = live(conn, "/chat")

    assert has_element?(view, "[data-role=conversation-rail]")
    assert has_element?(view, "[data-role=new-conversation]", "New chat")
    assert [{_id, "New chat", true}] = rail_items(view)
  end

  test "sending names the conversation from the first message and persists it", %{conn: conn} do
    {conn, identity} = scenario_authenticated_conn(conn, "chat-conv-persist", ["admin"])
    {:ok, view, _html} = live(conn, "/chat")

    submit_visitor_message(view, "First chat topic")
    send(view.pid, {:codex, view.pid, :turn_completed})

    assert [{_id, "First chat topic", true}] = rail_items(view)

    {:ok, reloaded, _html} = live(conn, "/chat")

    assert [{_id, "First chat topic", true}] = rail_items(reloaded)
    assert has_element?(reloaded, "[data-role=user-message]", "First chat topic")

    {:ok, conversations, _record} = CodexChat.load_conversations(identity.user_id)
    assert [%{title: "First chat topic"}] = CodexChat.list_conversations(conversations)
  end

  test "a new chat starts empty and switching keeps each conversation", %{conn: conn} do
    {conn, _identity} = scenario_authenticated_conn(conn, "chat-conv-switch", ["admin"])
    {:ok, view, _html} = live(conn, "/chat")

    submit_visitor_message(view, "First chat topic")
    send(view.pid, {:codex, view.pid, :turn_completed})

    view |> element("[data-role=new-conversation]") |> render_click()
    assert [{_second, "New chat", true}, {_first, "First chat topic", false}] = rail_items(view)
    refute has_element?(view, "[data-role=user-message]")

    submit_visitor_message(view, "Second chat topic")
    send(view.pid, {:codex, view.pid, :turn_completed})

    [{second_id, "Second chat topic", true}, {first_id, "First chat topic", false}] =
      rail_items(view)

    render_patch(view, "/chat?conversation=#{first_id}")

    assert [{^first_id, "First chat topic", true}, {^second_id, "Second chat topic", false}] =
             rail_items(view)

    assert has_element?(view, "[data-role=user-message]", "First chat topic")
    refute has_element?(view, "[data-role=user-message]", "Second chat topic")

    render_patch(view, "/chat?conversation=#{second_id}")
    assert has_element?(view, "[data-role=user-message]", "Second chat topic")
    refute has_element?(view, "[data-role=user-message]", "First chat topic")
  end

  test "an unknown conversation parameter keeps the current conversation", %{conn: conn} do
    {conn, _identity} = scenario_authenticated_conn(conn, "chat-conv-unknown", ["admin"])
    {:ok, view, _html} = live(conn, "/chat")
    [{id, "New chat", true}] = rail_items(view)

    render_patch(view, "/chat?conversation=missing-conversation")

    assert [{^id, "New chat", true}] = rail_items(view)
  end

  test "deleting the selected conversation connects its fallback", %{conn: conn} do
    {conn, _identity} = scenario_authenticated_conn(conn, "chat-conv-delete", ["admin"])
    {:ok, view, _html} = live(conn, "/chat")

    submit_visitor_message(view, "First chat topic")
    send(view.pid, {:codex, view.pid, :turn_completed})

    view |> element("[data-role=new-conversation]") |> render_click()
    [{second_id, _, true}, {first_id, "First chat topic", false}] = rail_items(view)
    flush_fixture_opens()

    view
    |> element("[data-role=delete-conversation][phx-value-id=\"#{second_id}\"]")
    |> render_click()

    assert [{^first_id, "First chat topic", true}] = rail_items(view)
    assert has_element?(view, "[data-role=user-message]", "First chat topic")
    assert_received {:codex_fixture_session, {:open, _owner, {nil, _, _, :read_only}}}
  end

  test "deleting another conversation keeps the session", %{conn: conn} do
    {conn, _identity} = scenario_authenticated_conn(conn, "chat-conv-delete-other", ["admin"])
    {:ok, view, _html} = live(conn, "/chat")

    submit_visitor_message(view, "First chat topic")
    send(view.pid, {:codex, view.pid, :turn_completed})

    view |> element("[data-role=new-conversation]") |> render_click()
    [{_second, _, true}, {first_id, "First chat topic", false}] = rail_items(view)
    flush_fixture_opens()

    view
    |> element("[data-role=delete-conversation][phx-value-id=\"#{first_id}\"]")
    |> render_click()

    assert [{_only, "New chat", true}] = rail_items(view)
    refute_received {:codex_fixture_session, {:open, _, _}}
  end

  test "renaming updates the title and a blank title is refused", %{conn: conn} do
    {conn, _identity} = scenario_authenticated_conn(conn, "chat-conv-rename", ["admin"])
    {:ok, view, _html} = live(conn, "/chat")
    [{id, "New chat", true}] = rail_items(view)

    view
    |> element("form[phx-submit=rename_conversation]")
    |> render_submit(%{"conversation_id" => id, "title" => "  Renamed chat  "})

    assert [{^id, "Renamed chat", true}] = rail_items(view)

    view
    |> element("form[phx-submit=rename_conversation]")
    |> render_submit(%{"conversation_id" => id, "title" => "   "})

    assert [{^id, "Renamed chat", true}] = rail_items(view)

    view
    |> element("form[phx-submit=rename_conversation]")
    |> render_submit(%{"conversation_id" => "missing-conversation", "title" => "Nope"})

    assert [{^id, "Renamed chat", true}] = rail_items(view)
  end

  test "a forged selection changes nothing", %{conn: conn} do
    {conn, _identity} = scenario_authenticated_conn(conn, "chat-conv-forged", ["admin"])
    {:ok, view, _html} = live(conn, "/chat")
    [{id, "New chat", true}] = rail_items(view)

    render_hook(view, "select_conversation", %{"id" => "missing-conversation"})
    render_hook(view, "delete_conversation", %{"id" => "missing-conversation"})

    assert [{^id, "New chat", true}] = rail_items(view)
  end

  test "tabs switch without a Codex session when no model is available", %{conn: conn} do
    with_catalog(Enum.reject(CodexFixtureModels.all(), &(&1.id == "gpt-6-luna")))

    {conn, _identity} = scenario_authenticated_conn(conn, "chat-conv-unavailable", ["children"])
    {:ok, view, _html} = live(conn, "/chat")

    assert [{first_id, "New chat", true}] = rail_items(view)

    view |> element("[data-role=new-conversation]") |> render_click()

    assert [{_second, "New chat", true}, {^first_id, "New chat", false}] =
             rail_items(view)

    render_patch(view, "/chat?conversation=#{first_id}")

    assert [{^first_id, "New chat", true}, {_second, "New chat", false}] =
             rail_items(view)
  end

  test "a legacy single-transcript chat restores into one conversation", %{conn: conn} do
    {conn, identity} = scenario_authenticated_conn(conn, "chat-conv-legacy", ["admin"])

    {:ok, chat} = Transcript.submit(Transcript.new(), "Legacy topic")
    assert {:ok, _record} = CodexChat.save_transcript(identity.user_id, chat, nil)

    {:ok, view, _html} = live(conn, "/chat")

    assert [{_id, "Legacy topic", true}] = rail_items(view)
    assert has_element?(view, "[data-role=user-message]", "Legacy topic")

    send(view.pid, {:codex, view.pid, :turn_completed})
    submit_visitor_message(view, "Continued")
    assert has_element?(view, "[data-role=user-message]", "Continued")
    assert has_element?(view, "[data-role=user-message]", "Legacy topic")
  end

  defp rail_items(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-role=conversation-item]")
    |> Enum.map(fn item ->
      id = item |> LazyHTML.attribute("data-conversation-id") |> hd()

      title =
        item
        |> LazyHTML.query("[data-role=select-conversation]")
        |> LazyHTML.text()
        |> String.trim()

      selected = LazyHTML.attribute(item, "aria-current") == ["true"]
      {id, title, selected}
    end)
    |> Enum.sort_by(fn {_id, _title, selected} -> selected end, :desc)
  end

  defp submit_visitor_message(view, prompt) do
    view
    |> element("#chat-composer-form")
    |> render_submit(%{"chat" => %{"prompt" => prompt}})
  end

  defp flush_fixture_opens do
    receive do
      {:codex_fixture_session, {:open, _, _}} -> flush_fixture_opens()
    after
      0 -> :ok
    end
  end

  defp with_catalog(models) do
    :ok = Supervisor.terminate_child(BnestApp.Supervisor, CodexChat.ModelCatalog)
    start_supervised!({CodexChat.ModelCatalog, models: models})

    on_exit(fn ->
      {:ok, _pid} = Supervisor.restart_child(BnestApp.Supervisor, CodexChat.ModelCatalog)
    end)
  end
end
