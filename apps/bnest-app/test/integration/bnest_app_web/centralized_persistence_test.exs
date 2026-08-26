defmodule BnestAppWeb.CentralizedPersistenceTest do
  use BnestAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BnestApp.DataRepository

  test "fresh authenticated chat ignores unconfirmed browser state and persists centrally", %{
    conn: conn,
    test_identity: identity
  } do
    browser_snapshot =
      Jason.encode!(%{
        "version" => 2,
        "thread_id" => "unconfirmed-browser-thread",
        "model" => "gpt-5.6-terra",
        "reasoning_effort" => "medium",
        "messages" => [
          %{
            "id" => 1,
            "role" => "visitor",
            "content" => "Unconfirmed browser value",
            "update_count" => 0
          },
          %{
            "id" => 2,
            "role" => "assistant",
            "content" => "Unconfirmed browser response",
            "update_count" => 1
          }
        ]
      })

    conn = put_connect_params(conn, %{"chat" => browser_snapshot})
    {:ok, view, _html} = live(conn, "/chat")
    refute has_element?(view, "[data-role=user-message]", "Unconfirmed browser value")

    render_submit(view, "send", %{"chat" => %{"prompt" => "Central only"}})
    send(view.pid, {:codex, view.pid, {:thread_started, "fixture-central-thread"}})
    send(view.pid, {:codex, view.pid, {:assistant_update, "Central response"}})
    send(view.pid, {:codex, view.pid, :turn_completed})

    record = await_record(:chat, identity.user_id)
    assert record["sourceImportId"] == nil
    assert Enum.any?(record["state"]["messages"], &(&1["content"] == "Central only"))

    %{proxy: {ref, _topic, _}} = view
    refute_receive {^ref, {:push_event, "persist-chat", _snapshot}}, 50
  end

  test "fresh authenticated learning state persists centrally and reloads from the server", %{
    conn: conn,
    test_identity: identity
  } do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view |> element("button", "Belajar 3 Pasangan") |> render_click()
    view |> element("button", "Aku sudah ingat") |> render_click()

    record = await_record(:sifat_allah, identity.user_id)
    assert record["sourceImportId"] == nil
    assert "wujud" in record["progress"]["learned_ids"]

    %{proxy: {ref, _topic, _}} = view
    refute_receive {^ref, {:push_event, "persist-sifat-allah", _snapshot}}, 50

    {:ok, reloaded, _html} = live(recycle(conn), "/apps/sifat-allah")
    assert has_element?(reloaded, ".sifat-stage", "6 dari 120 soal sudah hafal")
  end

  defp await_record(type, user_id, attempts \\ 100)

  defp await_record(type, user_id, attempts) when attempts > 0 do
    case DataRepository.read(type, user_id) do
      {:ok, record} ->
        record

      {:error, :missing} ->
        Process.sleep(10)
        await_record(type, user_id, attempts - 1)
    end
  end

  defp await_record(type, user_id, 0) do
    flunk("central #{type} record was not created for synthetic user #{user_id}")
  end
end
