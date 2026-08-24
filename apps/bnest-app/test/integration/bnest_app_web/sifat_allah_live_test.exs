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

  test "removes a difficult pair after a correct focused review answer", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/apps/sifat-allah")

    view
    |> element("button", "Latihan Ujian")
    |> render_click()

    view
    |> element("button", "Lemah")
    |> render_click()

    view
    |> element("button", "← Kembali ke misi")
    |> render_click()

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

    view
    |> element("button", "← Kembali ke misi")
    |> render_click()

    view
    |> element("button", "Ulangi yang masih bikin bingung (2)")
    |> render_click()

    view
    |> element("[data-role=review-question] button", "Lemah")
    |> render_click()

    assert has_element?(view, "[role=status]", "Belum tepat. Coba sekali lagi, ya.")

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

  test "falls back safely when a saved session is not usable", %{conn: conn} do
    invalid_sessions = [
      %{"mode" => "study", "lesson_ids" => [], "lesson_index" => 0},
      %{"mode" => "quiz", "quiz_pair_id" => "unknown", "quiz_kind" => "meaning"},
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
       }, "Belum tepat. Nanti kita ulang lagi, ya."}
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

  defp snapshot(session, progress \\ SifatAllah.progress()),
    do: Map.put(progress, "session", session)
end
