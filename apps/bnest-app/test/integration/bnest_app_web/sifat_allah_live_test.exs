defmodule BnestAppWeb.SifatAllahLiveTest do
  use BnestAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BnestApp.SifatAllah

  test "moves through a short lesson and returns to the dashboard", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Belajar 3 Pasangan")
    |> render_click()

    assert has_element?(view, "[data-role=study-card]", "Wujud")

    view
    |> element("button", "Pasangan berikutnya →")
    |> render_click()

    assert has_element?(view, "[data-role=study-card]", "Qidam")

    view
    |> element("button", "Pasangan berikutnya →")
    |> render_click()

    assert has_element?(view, "[data-role=study-card]", "Baqa’")

    view
    |> element("button", "Pasangan berikutnya →")
    |> render_click()

    assert has_element?(view, "button", "Latihan Ujian")
  end

  test "marks wajib and mustahil cards with their memory colors", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Belajar 3 Pasangan")
    |> render_click()

    assert has_element?(view, "[data-role=study-card] [data-memory-color=wajib]", "SIFAT WAJIB")

    assert has_element?(
             view,
             "[data-role=study-card] [data-memory-color=mustahil]",
             "SIFAT MUSTAHIL"
           )
  end

  test "does not repeat completed pairs in a new lesson", %{conn: conn} do
    all_learned =
      SifatAllah.curriculum()
      |> Enum.map(& &1.id)
      |> Enum.reduce(SifatAllah.progress(), &SifatAllah.remember(&2, &1))

    conn =
      put_connect_params(conn, %{
        "sifat_allah" => Jason.encode!(snapshot(%{"mode" => "dashboard"}, all_learned))
      })

    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    assert has_element?(view, "button[phx-click=start-learning][disabled]")
    assert has_element?(view, "[role=status]", "Semua pasangan sudah kamu hafal")
    assert has_element?(view, "button", "Latihan Ujian")

    render_click(view, "start-learning", %{})

    assert has_element?(view, "button[phx-click=start-learning][disabled]")
  end

  test "keeps the quiz cycling after every pair is remembered", %{conn: conn} do
    all_remembered =
      Enum.reduce(SifatAllah.curriculum(), SifatAllah.progress(), fn pair, progress ->
        SifatAllah.remember(progress, pair.id)
      end)

    conn =
      put_connect_params(conn, %{
        "sifat_allah" => Jason.encode!(snapshot(%{"mode" => "dashboard"}, all_remembered))
      })

    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Latihan Ujian")
    |> render_click()

    assert has_element?(view, "h2", "Apa arti Wujud?")

    view
    |> element("button", "Soal berikutnya →")
    |> render_click()

    assert has_element?(view, "h2", "Apa lawan dari Qidam?")
  end

  test "emits a celebration after a correct quiz answer", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Latihan Ujian")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", _quiz_snapshot)

    view
    |> element("button", "Ada")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", _answer_snapshot)
    assert_push_event(view, "sifat-celebrate", %{})

    assert has_element?(
             view,
             "[data-testid=sifat-allah-progress]",
             "1 dari 120 soal sudah hafal"
           )

    assert has_element?(
             view,
             "[data-testid=sifat-allah-unmastered-count]",
             "119 soal masih perlu diulang"
           )
  end

  test "locks a quiz answer and advances only once after its timer fires", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    render_click(view, "start-quiz", %{})
    assert_push_event(view, "persist-sifat-allah", _quiz_snapshot)
    assert_push_event(view, "sifat-history-entry", %{})

    render_click(view, "answer", %{"answer" => "Ada"})
    assert_push_event(view, "persist-sifat-allah", answer_snapshot)

    assert answer_snapshot["correct_answers"] == 1
    assert has_element?(view, ".sifat-answer-grid button[disabled]")

    render_click(view, "answer", %{"answer" => "Dahulu"})
    assert has_element?(view, "[role=status]", "Betul!")
    assert has_element?(view, "[data-testid=sifat-allah-progress]", "1 dari 120 soal sudah hafal")

    send(view.pid, {:auto_advance, :quiz, 2})

    assert_push_event(view, "persist-sifat-allah", next_snapshot)
    assert next_snapshot["session"]["quiz_pair_id"] == "qidam"
    assert next_snapshot["session"]["quiz_kind"] == "wajib_opposite"
    assert has_element?(view, "h2", "Apa lawan dari Qidam?")
  end

  test "removes a difficult pair after a correct focused review answer", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Latihan Ujian")
    |> render_click()

    view
    |> element("button", "Lemah")
    |> render_click()

    return_to_mission(view)

    view
    |> element("button", "Ulangi yang masih bikin bingung (1)")
    |> render_click()

    assert has_element?(view, "[data-role=review-question]", "Apa arti Wujud?")

    view
    |> element("[data-role=review-question] button", "Ada")
    |> render_click()

    assert has_element?(view, "[role=status]", "Mantap! Wujud sudah kamu kuasai.")

    view
    |> element("button", "Selesai dan kembali ke misi")
    |> render_click()

    assert has_element?(view, "button", "Ulangi yang masih bikin bingung (0)")
  end

  test "alternates focused review pairs after an incorrect answer", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Latihan Ujian")
    |> render_click()

    view
    |> element("button", "Lemah")
    |> render_click()

    view
    |> element("button", "Soal berikutnya →")
    |> render_click()

    view
    |> element("button", "Fana’")
    |> render_click()

    return_to_mission(view)

    view
    |> element("button", "Ulangi yang masih bikin bingung (2)")
    |> render_click()

    view
    |> element("[data-role=review-question] button", "Lemah")
    |> render_click()

    assert has_element?(
             view,
             "[role=status]",
             "Belum tepat. Jawaban yang benar: Ada. Coba sekali lagi, ya."
           )

    view
    |> element("button", "Soal ulangi berikutnya →")
    |> render_click()

    assert has_element?(view, "[data-role=review-question]", "Apa lawan dari Qidam?")
  end

  test "restores the active study card from a browser snapshot", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Belajar 3 Pasangan")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", _start_snapshot)

    view
    |> element("button", "Pasangan berikutnya →")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", snapshot)

    conn = put_connect_params(conn, %{"sifat_allah" => Jason.encode!(snapshot)})
    {:ok, resumed_view, _html} = live(conn, "/apps/sifat-allah")

    assert has_element?(resumed_view, "[data-role=study-card]", "Qidam")
  end

  test "restores the active quiz question from a browser snapshot", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Latihan Ujian")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", _start_snapshot)

    view
    |> element("button", "Soal berikutnya →")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", snapshot)

    conn = put_connect_params(conn, %{"sifat_allah" => Jason.encode!(snapshot)})
    {:ok, resumed_view, _html} = live(conn, "/apps/sifat-allah")

    assert has_element?(resumed_view, "h2", "Apa lawan dari Qidam?")
  end

  test "retests marked pairs and keeps the learned quiz after a reload", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Belajar 3 Pasangan")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", _lesson_snapshot)

    view
    |> element("button", "Aku sudah ingat")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", _remember_wujud_snapshot)

    view
    |> element("button", "Pasangan berikutnya →")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", _qidam_snapshot)

    view
    |> element("button", "Aku sudah ingat")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", _remember_qidam_snapshot)

    _dashboard_snapshot = return_to_mission(view)

    view
    |> element("button", "Ulangi yang sudah hafal (12)")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", start_snapshot)
    assert start_snapshot["session"]["quiz_scope"] == "learned"
    assert has_element?(view, ".sifat-quiz", "SOAL YANG SUDAH HAFAL")
    assert has_element?(view, "h2", "Apa arti Wujud?")

    view
    |> element("button", "Soal berikutnya →")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", _next_snapshot)
    assert has_element?(view, "h2", "Apa lawan dari Wujud?")

    view
    |> element("button", "← Soal sebelumnya")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", snapshot)
    assert has_element?(view, "h2", "Apa arti Wujud?")

    conn = put_connect_params(conn, %{"sifat_allah" => Jason.encode!(snapshot)})
    {:ok, resumed_view, _html} = live(conn, "/apps/sifat-allah")

    assert has_element?(resumed_view, ".sifat-quiz", "SOAL YANG SUDAH HAFAL")
    assert has_element?(resumed_view, "h2", "Apa arti Wujud?")
  end

  test "ignores learned review when no pair has been marked", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    render_click(view, "start-learned-review", %{})

    assert has_element?(view, "button", "Belajar 3 Pasangan")
  end

  test "restores an active focused review question from a browser snapshot", %{conn: conn} do
    progress = SifatAllah.record_answer(SifatAllah.progress(), SifatAllah.pair("wujud"), false)

    conn =
      put_connect_params(conn, %{
        "sifat_allah" =>
          Jason.encode!(
            snapshot(
              %{
                "mode" => "review",
                "review_pair_id" => "wujud",
                "review_kind" => "meaning",
                "feedback" => nil
              },
              progress
            )
          )
      })

    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    assert has_element?(view, "[data-role=review-question]", "Apa arti Wujud?")
  end

  test "restores an opposite-meaning quiz question from a browser snapshot", %{conn: conn} do
    conn =
      put_connect_params(conn, %{
        "sifat_allah" =>
          Jason.encode!(
            snapshot(%{
              "mode" => "quiz",
              "quiz_pair_id" => "baqa",
              "quiz_kind" => "opposite_meaning",
              "quiz_scope" => "all",
              "feedback" => nil
            })
          )
      })

    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    assert has_element?(view, "h2", "Apa arti Fana’?")
  end

  test "migrates a version 2 browser snapshot and immediately persists version 3", %{conn: conn} do
    legacy_snapshot =
      snapshot(%{
        "mode" => "quiz",
        "quiz_pair_id" => "qidam",
        "quiz_kind" => "wajib_opposite",
        "quiz_scope" => "all",
        "feedback" => nil
      })
      |> Map.put("version", 2)

    conn = put_connect_params(conn, %{"sifat_allah" => Jason.encode!(legacy_snapshot)})
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    assert_push_event(view, "persist-sifat-allah", migrated_snapshot)
    assert migrated_snapshot["version"] == 3
    assert migrated_snapshot["mastered_key_ids"] == legacy_snapshot["mastered_key_ids"]
    assert migrated_snapshot["session"]["quiz_pair_id"] == "qidam"
    assert has_element?(view, "h2", "Apa lawan dari Qidam?")
  end

  test "falls back safely when a saved session is not usable", %{conn: conn} do
    invalid_sessions = [
      %{"mode" => "study", "lesson_ids" => [], "lesson_index" => 0},
      %{"mode" => "quiz", "quiz_pair_id" => "unknown", "quiz_kind" => "meaning"},
      %{
        "mode" => "quiz",
        "quiz_pair_id" => "wujud",
        "quiz_kind" => "meaning",
        "quiz_scope" => "learned"
      },
      %{"mode" => "review", "review_pair_id" => "unknown", "review_kind" => "meaning"},
      %{"mode" => "dashboard"},
      %{"mode" => "unknown"}
    ]

    Enum.each(invalid_sessions, fn session ->
      conn = put_connect_params(conn, %{"sifat_allah" => Jason.encode!(snapshot(session))})
      {:ok, view, _html} = live(conn, "/apps/sifat-allah")

      assert has_element?(view, "button", "Belajar 3 Pasangan")
    end)
  end

  test "restores saved quiz feedback", %{conn: conn} do
    sessions = [
      {%{
         "mode" => "quiz",
         "quiz_pair_id" => "wujud",
         "quiz_kind" => "meaning",
         "feedback" => "success"
       }, "Betul!"},
      {%{
         "mode" => "quiz",
         "quiz_pair_id" => "qidam",
         "quiz_kind" => "opposite",
         "feedback" => "retry"
       }, "Belum tepat. Jawaban yang benar: Hudus. Nanti kita ulang lagi, ya."}
    ]

    Enum.each(sessions, fn {session, feedback} ->
      conn = put_connect_params(conn, %{"sifat_allah" => Jason.encode!(snapshot(session))})
      {:ok, view, _html} = live(conn, "/apps/sifat-allah")

      assert has_element?(view, "[role=status]", feedback)
    end)
  end

  test "ignores an unrecognized swipe direction", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Belajar 3 Pasangan")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", _start_snapshot)
    render_hook(view, "swipe-study", %{"direction" => "up"})

    assert has_element?(view, "[data-role=study-card]", "Wujud")
  end

  test "returns to the mission when browser history goes back from a quiz", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Latihan Ujian")
    |> render_click()

    assert_push_event(view, "persist-sifat-allah", _quiz_snapshot)
    assert_push_event(view, "sifat-history-entry", %{})

    render_hook(view, "dashboard", %{})

    assert_push_event(view, "persist-sifat-allah", dashboard_snapshot)
    assert dashboard_snapshot["session"] == %{"mode" => "dashboard"}
    assert has_element?(view, "button", "Belajar 3 Pasangan")
    assert has_element?(view, "button", "Latihan Ujian")
  end

  defp return_to_mission(view) do
    view
    |> element("button", "← Kembali ke misi")
    |> render_click()

    assert_push_event(view, "sifat-history-back", %{})
    render_hook(view, "dashboard", %{})
    assert_push_event(view, "persist-sifat-allah", snapshot)
    snapshot
  end

  defp snapshot(session, progress \\ SifatAllah.progress()),
    do: Map.put(progress, "session", session)
end
