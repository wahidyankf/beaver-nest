defmodule BnestAppWeb.SifatAllahLive do
  use BnestAppWeb, :live_view

  alias BnestApp.SifatAllah

  @max_snapshot_bytes 10_000
  @quiz_auto_advance_delay 5_000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    state = restore_state(socket)

    {:ok,
     socket
     |> assign(state)}
  end

  @impl Phoenix.LiveView
  def handle_event("start-learning", _params, socket) do
    lesson_pairs = SifatAllah.lesson_pairs(socket.assigns.progress)

    case lesson_pairs do
      [] ->
        {:noreply, socket}

      _pairs ->
        {:noreply,
         socket
         |> cancel_auto_advance()
         |> assign(:mode, :study)
         |> assign(:lesson_pairs, lesson_pairs)
         |> assign(:lesson_index, 0)
         |> assign(:feedback, nil)
         |> persist_snapshot()
         |> push_history_entry()}
    end
  end

  def handle_event("next-pair", _params, socket) do
    next_index = socket.assigns.lesson_index + 1

    if next_index < length(socket.assigns.lesson_pairs) do
      {:noreply,
       socket |> assign(:lesson_index, next_index) |> assign(:feedback, nil) |> persist_snapshot()}
    else
      {:noreply,
       socket |> assign(:mode, :dashboard) |> assign(:feedback, nil) |> persist_snapshot()}
    end
  end

  def handle_event("previous-pair", _params, socket) do
    if socket.assigns.lesson_index > 0 do
      {:noreply,
       socket
       |> assign(:lesson_index, socket.assigns.lesson_index - 1)
       |> assign(:feedback, nil)
       |> persist_snapshot()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("swipe-study", %{"direction" => "left"}, socket),
    do: handle_event("next-pair", %{}, socket)

  def handle_event("swipe-study", %{"direction" => "right"}, socket),
    do: handle_event("previous-pair", %{}, socket)

  def handle_event("swipe-study", _params, socket), do: {:noreply, socket}

  def handle_event("swipe-quiz", %{"direction" => "left"}, socket),
    do: handle_event("next-question", %{}, socket)

  def handle_event("swipe-quiz", %{"direction" => "right"}, socket),
    do: handle_event("previous-question", %{}, socket)

  def handle_event("swipe-quiz", _params, socket), do: {:noreply, socket}

  def handle_event("remember-pair", _params, socket) do
    pair = current_study_pair(socket.assigns)
    progress = SifatAllah.remember(socket.assigns.progress, pair.id)

    {:noreply,
     socket
     |> assign(:progress, progress)
     |> assign(:feedback, %{kind: :success, text: "Hebat! Kamu sudah ingat #{pair.wajib}."})
     |> persist_snapshot()}
  end

  def handle_event("start-quiz", _params, socket) do
    {:noreply,
     socket
     |> cancel_auto_advance()
     |> assign(:mode, :quiz)
     |> assign(:quiz_pair, SifatAllah.quiz_pair(socket.assigns.progress))
     |> assign(:quiz_kind, :wajib_meaning)
     |> assign(:quiz_scope, :all)
     |> assign(:feedback, nil)
     |> persist_snapshot()
     |> push_history_entry()}
  end

  def handle_event("start-learned-review", _params, socket) do
    case SifatAllah.first_mastered_question(socket.assigns.progress) do
      nil ->
        {:noreply, socket}

      {pair, kind} ->
        {:noreply,
         socket
         |> cancel_auto_advance()
         |> assign(:mode, :quiz)
         |> assign(:quiz_pair, pair)
         |> assign(:quiz_kind, kind)
         |> assign(:quiz_scope, :learned)
         |> assign(:feedback, nil)
         |> persist_snapshot()
         |> push_history_entry()}
    end
  end

  def handle_event("start-review", _params, socket) do
    case SifatAllah.first_review_question(socket.assigns.progress) do
      nil ->
        {:noreply, socket}

      {pair, kind} ->
        {:noreply,
         socket
         |> cancel_auto_advance()
         |> assign(:mode, :review)
         |> assign(:review_pair, pair)
         |> assign(:review_kind, kind)
         |> assign(:feedback, nil)
         |> persist_snapshot()
         |> push_history_entry()}
    end
  end

  def handle_event("answer", %{"answer" => _answer}, %{assigns: %{feedback: feedback}} = socket)
      when not is_nil(feedback),
      do: {:noreply, socket}

  def handle_event("answer", %{"answer" => answer}, socket) do
    pair = socket.assigns.quiz_pair
    correct? = SifatAllah.correct_answer?(pair, socket.assigns.quiz_kind, answer)

    progress =
      socket.assigns.progress
      |> record_quiz_answer(pair, socket.assigns.quiz_kind, correct?, socket.assigns.quiz_scope)

    feedback =
      if correct? do
        %{kind: :success, text: "Betul!"}
      else
        retry_feedback("Nanti kita ulang lagi, ya.", pair, socket.assigns.quiz_kind)
      end

    {:noreply,
     socket
     |> assign(:progress, progress)
     |> assign(:feedback, feedback)
     |> persist_snapshot()
     |> schedule_auto_advance(:quiz)
     |> celebrate_if_correct(correct?)}
  end

  def handle_event(
        "review-answer",
        %{"answer" => _answer},
        %{assigns: %{feedback: feedback}} = socket
      )
      when not is_nil(feedback),
      do: {:noreply, socket}

  def handle_event("review-answer", %{"answer" => answer}, socket) do
    pair = socket.assigns.review_pair
    correct? = SifatAllah.correct_answer?(pair, socket.assigns.review_kind, answer)

    progress =
      socket.assigns.progress
      |> SifatAllah.record_answer(pair, socket.assigns.review_kind, correct?)

    feedback =
      if correct? do
        %{kind: :success, text: "Mantap! #{pair.wajib} sudah kamu kuasai."}
      else
        retry_feedback("Coba sekali lagi, ya.", pair, socket.assigns.review_kind)
      end

    {:noreply,
     socket
     |> assign(:progress, progress)
     |> assign(:feedback, feedback)
     |> persist_snapshot()
     |> schedule_auto_advance(:review)
     |> celebrate_if_correct(correct?)}
  end

  def handle_event("next-question", _params, socket) do
    move_quiz_question(socket, :next)
  end

  def handle_event("previous-question", _params, socket) do
    move_quiz_question(socket, :previous)
  end

  def handle_event("next-review-question", _params, socket) do
    case SifatAllah.next_review_question(
           socket.assigns.progress,
           socket.assigns.review_pair,
           socket.assigns.review_kind
         ) do
      nil ->
        handle_event("dashboard", %{}, socket)

      {pair, kind} ->
        {:noreply,
         socket
         |> cancel_auto_advance()
         |> assign(:review_pair, pair)
         |> assign(:review_kind, kind)
         |> assign(:feedback, nil)
         |> persist_snapshot()}
    end
  end

  def handle_event("dashboard", _params, socket) do
    {:noreply,
     socket
     |> cancel_auto_advance()
     |> assign(:mode, :dashboard)
     |> assign(:feedback, nil)
     |> persist_snapshot()}
  end

  def handle_event("back-to-mission", _params, socket) do
    {:noreply, push_event(socket, "sifat-history-back", %{})}
  end

  @impl Phoenix.LiveView
  def handle_info(
        {:auto_advance, :quiz, token},
        %{assigns: %{auto_advance_token: token, feedback: feedback}} = socket
      )
      when not is_nil(feedback) do
    handle_event("next-question", %{}, socket)
  end

  def handle_info(
        {:auto_advance, :review, token},
        %{assigns: %{auto_advance_token: token, feedback: feedback}} = socket
      )
      when not is_nil(feedback) do
    handle_event("next-review-question", %{}, socket)
  end

  def handle_info({:auto_advance, _mode, _token}, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main id="sifat-allah-app" class="sifat-shell" phx-hook="SifatHistory">
      <header class="sifat-topbar">
        <a href="/" class="sifat-home-link">← Beaver Nest</a>
        <p class="sifat-saved-note">Tersimpan di browser ini</p>
      </header>

      <section class="sifat-stage" aria-labelledby="sifat-title">
        <div class="sifat-title-card">
          <p class="sifat-kicker">MISI UJIAN BESOK</p>
          <h1 id="sifat-title">Misi Hafal 40 Sifat Allah</h1>
          <p>20 pasangan: nama, arti, dan lawannya</p>
        </div>

        <section class="sifat-progress" aria-label="Kemajuan hafalan">
          <div>
            <span>PROGRES HAFALAN</span>
            <strong class="sifat-percent" data-testid="sifat-allah-percent">
              {SifatAllah.mastery_percent(@progress)}% hafal
            </strong>
            <strong data-testid="sifat-allah-progress">
              {SifatAllah.mastered_count(@progress)} dari {SifatAllah.total_count()} soal sudah hafal
            </strong>
            <span class="sifat-unmastered-count" data-testid="sifat-allah-unmastered-count">
              {SifatAllah.unmastered_count(@progress)} soal masih perlu diulang
            </span>
            <span class="sifat-correct-count">
              {SifatAllah.correct_count(@progress)} jawaban benar
            </span>
          </div>
          <div class="sifat-pebble-trail" aria-hidden="true">
            <i
              :for={index <- 1..20}
              class={if index <= SifatAllah.learned_count(@progress), do: "is-known"}
            ></i>
          </div>
        </section>

        <.dashboard :if={@mode == :dashboard} progress={@progress} />
        <.study :if={@mode == :study} assigns={assigns} />
        <.quiz :if={@mode == :quiz} assigns={assigns} />
        <.review :if={@mode == :review} assigns={assigns} />
      </section>
      <div id="sifat-celebrations" class="sifat-celebrations" aria-hidden="true"></div>
    </main>
    """
  end

  attr(:progress, :map, required: true)

  defp dashboard(assigns) do
    assigns = assign(assigns, :lesson_available?, SifatAllah.lesson_pairs(assigns.progress) != [])

    ~H"""
    <section class="sifat-dashboard" aria-label="Pilih latihan">
      <p class="sifat-instruction">
        Pilih satu langkah kecil. Kamu nggak perlu hafal semuanya sekaligus.
      </p>
      <section class="sifat-key-map" aria-labelledby="sifat-key-map-title">
        <div>
          <p>40 nama sifat, 120 soal hafalan</p>
          <h2 id="sifat-key-map-title">6 soal tiap pasangan</h2>
          <small>Setiap hubungan ditanya dari dua arah supaya hafalnya lebih kuat.</small>
        </div>
        <ol>
          <li class="sifat-wajib-key" data-memory-color="wajib">
            <span aria-hidden="true">1</span>
            <strong>Sifat wajib</strong>
            <small>↔ artinya</small>
          </li>
          <li class="sifat-mustahil-key" data-memory-color="mustahil">
            <span aria-hidden="true">2</span>
            <strong>Sifat mustahil</strong>
            <small>↔ artinya</small>
          </li>
          <li class="sifat-opposite-key">
            <span aria-hidden="true">3</span>
            <strong>Dua sifat itu</strong>
            <small>↔ saling berlawanan</small>
          </li>
        </ol>
      </section>
      <div class="sifat-actions">
        <button
          type="button"
          class="sifat-primary-action"
          phx-click="start-learning"
          disabled={not @lesson_available?}
        >
          <span aria-hidden="true">◎</span>
          <strong>Belajar 3 Pasangan</strong>
          <small>Lihat, baca, lalu ingat</small>
        </button>
        <button type="button" class="sifat-secondary-action" phx-click="start-quiz">
          <span aria-hidden="true">✦</span>
          <strong>Latihan Ujian</strong>
          <small>Uji nama, arti, dan lawannya</small>
        </button>
      </div>
      <p :if={not @lesson_available?} class="sifat-feedback is-success" role="status">
        Semua pasangan sudah kamu hafal. Yuk, kuatkan dengan Latihan Ujian.
      </p>
      <button
        type="button"
        class="sifat-review-action"
        phx-click="start-review"
        disabled={@progress["review_key_ids"] == []}
      >
        Ulangi yang masih bikin bingung ({length(@progress["review_key_ids"])})
      </button>
      <button
        type="button"
        class="sifat-review-action"
        phx-click="start-learned-review"
        disabled={@progress["mastered_key_ids"] == []}
      >
        Ulangi yang sudah hafal ({length(@progress["mastered_key_ids"])})
      </button>
    </section>
    """
  end

  attr(:assigns, :map, required: true)

  defp study(assigns) do
    pair = current_study_pair(assigns.assigns)

    assigns = assign(assigns, :pair, pair)

    ~H"""
    <section class="sifat-study" aria-label="Belajar pasangan sifat">
      <p class="sifat-step">
        Pasangan {@assigns.lesson_index + 1} dari {length(@assigns.lesson_pairs)}
      </p>
      <article
        id="sifat-study-card"
        class="sifat-study-card"
        data-role="study-card"
        phx-hook="SifatSwipe"
      >
        <div class="sifat-side sifat-wajib-side" data-memory-color="wajib">
          <span>SIFAT WAJIB</span>
          <strong>{@pair.wajib}</strong>
          <p>{@pair.wajib_meaning}</p>
        </div>
        <div class="sifat-pair-arrow" aria-hidden="true">↔</div>
        <div class="sifat-side sifat-mustahil-side" data-memory-color="mustahil">
          <span>SIFAT MUSTAHIL</span>
          <strong>{@pair.mustahil}</strong>
          <p>{@pair.mustahil_meaning}</p>
        </div>
      </article>
      <section class="sifat-pair-keys" aria-labelledby="sifat-pair-keys-title">
        <p>6 SOAL PASANGAN INI</p>
        <h2 id="sifat-pair-keys-title">Kenali tiga hubungan dari dua arah</h2>
        <ol>
          <li class="sifat-wajib-key">
            <span aria-hidden="true">1</span> {@pair.wajib} ↔ {@pair.wajib_meaning}
          </li>
          <li class="sifat-mustahil-key">
            <span aria-hidden="true">2</span> {@pair.mustahil} ↔ {@pair.mustahil_meaning}
          </li>
          <li class="sifat-opposite-key">
            <span aria-hidden="true">3</span> {@pair.wajib} ↔ {@pair.mustahil}
          </li>
        </ol>
      </section>
      <p class="sifat-swipe-hint" aria-hidden="true">
        Geser kanan untuk kembali <span>·</span> geser kiri untuk lanjut
      </p>
      <p :if={@assigns.feedback} class={"sifat-feedback is-#{@assigns.feedback.kind}"} role="status">
        {@assigns.feedback.text}
      </p>
      <p :if={@assigns.feedback} class="sifat-auto-advance-note">
        Soal berikutnya muncul otomatis dalam 5 detik.
      </p>
      <div class="sifat-study-actions">
        <button
          type="button"
          class="sifat-quiet-action"
          phx-click="previous-pair"
          disabled={@assigns.lesson_index == 0}
        >
          ← Pasangan sebelumnya
        </button>
        <button type="button" class="sifat-quiet-action" phx-click="back-to-mission">← Kembali ke misi</button>
        <button type="button" class="sifat-primary-action" phx-click="remember-pair">
          Aku sudah ingat
        </button>
        <button type="button" class="sifat-quiet-action" phx-click="next-pair">
          Pasangan berikutnya →
        </button>
      </div>
    </section>
    """
  end

  attr(:assigns, :map, required: true)

  defp quiz(assigns) do
    pair = assigns.assigns.quiz_pair

    question = SifatAllah.question(pair, assigns.assigns.quiz_kind)

    options = SifatAllah.answer_options(pair, assigns.assigns.quiz_kind)
    revision_pairs = SifatAllah.review_pairs(assigns.assigns.progress)

    {label, step} =
      case assigns.assigns.quiz_scope do
        :learned -> {"Ulangi yang sudah hafal", "SOAL YANG SUDAH HAFAL"}
        :all -> {"Latihan ujian", "SOAL LATIHAN"}
      end

    assigns =
      assign(assigns,
        pair: pair,
        question: question,
        options: options,
        revision_pairs: revision_pairs,
        label: label,
        step: step
      )

    ~H"""
    <section class="sifat-quiz" aria-label={@label}>
      <p class="sifat-step">{@step}</p>
      <div
        id="sifat-quiz-question"
        class="sifat-quiz-question"
        data-role="quiz-question"
        data-swipe-event="swipe-quiz"
        phx-hook="SifatSwipe"
      >
        <h2>{@question}</h2>
        <div class="sifat-answer-grid">
          <button
            :for={option <- @options}
            type="button"
            phx-click="answer"
            phx-value-answer={option}
            disabled={not is_nil(@assigns.feedback)}
          >
            {option}
          </button>
        </div>
      </div>
      <p class="sifat-swipe-hint" aria-hidden="true">
        Geser kanan untuk soal sebelumnya <span>·</span> geser kiri untuk soal berikutnya
      </p>
      <p :if={@assigns.feedback} class={"sifat-feedback is-#{@assigns.feedback.kind}"} role="status">
        {@assigns.feedback.text}
      </p>
      <p :if={@assigns.feedback} class="sifat-auto-advance-note">
        Soal berikutnya muncul otomatis dalam 5 detik.
      </p>
      <button type="button" class="sifat-quiet-action" phx-click="previous-question">
        ← Soal sebelumnya
      </button>
      <button type="button" class="sifat-quiet-action" phx-click="next-question">Soal berikutnya →</button>
      <section
        class="sifat-revision-list"
        data-testid="sifat-allah-revision-list"
        aria-label="Ulangi ini"
      >
        <h3>Ulangi ini</h3>
        <p :if={@revision_pairs == []}>Belum ada. Mantap!</p>
        <ul :if={@revision_pairs != []}>
          <li :for={pair <- @revision_pairs}>{pair.wajib} — {pair.wajib_meaning}</li>
        </ul>
      </section>
      <button type="button" class="sifat-quiet-action" phx-click="back-to-mission">← Kembali ke misi</button>
    </section>
    """
  end

  attr(:assigns, :map, required: true)

  defp review(assigns) do
    pair = assigns.assigns.review_pair

    question = SifatAllah.question(pair, assigns.assigns.review_kind)

    options = SifatAllah.answer_options(pair, assigns.assigns.review_kind)
    remaining_count = length(assigns.assigns.progress["review_key_ids"])

    assigns =
      assign(assigns,
        pair: pair,
        question: question,
        options: options,
        remaining_count: remaining_count
      )

    ~H"""
    <section class="sifat-quiz sifat-focused-review" aria-label="Ulangi yang masih bikin bingung">
      <p class="sifat-step">SOAL ULANGI</p>
      <p class="sifat-review-count">Masih ada {@remaining_count} soal untuk dikuasai</p>
      <div id="sifat-review-question" class="sifat-quiz-question" data-role="review-question">
        <h2>{@question}</h2>
        <div class="sifat-answer-grid">
          <button
            :for={option <- @options}
            type="button"
            phx-click="review-answer"
            phx-value-answer={option}
            disabled={not is_nil(@assigns.feedback)}
          >
            {option}
          </button>
        </div>
      </div>
      <p :if={@assigns.feedback} class={"sifat-feedback is-#{@assigns.feedback.kind}"} role="status">
        {@assigns.feedback.text}
      </p>
      <button
        :if={@assigns.feedback}
        type="button"
        class="sifat-quiet-action"
        phx-click="next-review-question"
      >
        {if @remaining_count == 0, do: "Selesai dan kembali ke misi", else: "Soal ulangi berikutnya →"}
      </button>
      <button type="button" class="sifat-quiet-action" phx-click="back-to-mission">← Kembali ke misi</button>
    </section>
    """
  end

  defp current_study_pair(assigns), do: Enum.at(assigns.lesson_pairs, assigns.lesson_index)

  defp restore_state(socket) do
    if connected?(socket) do
      with %{"sifat_allah" => encoded} when is_binary(encoded) <- get_connect_params(socket),
           true <- byte_size(encoded) <= @max_snapshot_bytes,
           {:ok, snapshot} <- Jason.decode(encoded),
           {:ok, progress} <- SifatAllah.restore(snapshot) do
        restore_session(progress, snapshot["session"])
      else
        _invalid_or_missing -> default_state(SifatAllah.progress())
      end
    else
      default_state(SifatAllah.progress())
    end
  end

  defp default_state(progress) do
    %{
      progress: progress,
      mode: :dashboard,
      lesson_pairs: [],
      lesson_index: 0,
      quiz_pair: nil,
      quiz_kind: :wajib_meaning,
      quiz_scope: :all,
      review_pair: nil,
      review_kind: :wajib_meaning,
      feedback: nil,
      auto_advance_token: 0
    }
  end

  defp restore_session(
         progress,
         %{"mode" => "study", "lesson_ids" => ids, "lesson_index" => index} = session
       )
       when is_list(ids) and is_integer(index) do
    with {:ok, lesson_pairs} <- pairs_from_ids(ids),
         true <- index >= 0 and index < length(lesson_pairs) do
      pair = Enum.at(lesson_pairs, index)

      default_state(progress)
      |> Map.merge(%{
        mode: :study,
        lesson_pairs: lesson_pairs,
        lesson_index: index,
        feedback: study_feedback(session["feedback"], pair)
      })
    else
      _invalid_session -> default_state(progress)
    end
  end

  defp restore_session(
         progress,
         %{"mode" => "quiz", "quiz_pair_id" => pair_id, "quiz_kind" => quiz_kind} = session
       )
       when quiz_kind in [
              "wajib_meaning",
              "wajib_opposite",
              "mustahil_meaning",
              "meaning_wajib",
              "mustahil_opposite",
              "meaning_mustahil",
              "meaning",
              "opposite",
              "opposite_meaning"
            ] do
    case SifatAllah.pair(pair_id) do
      nil ->
        default_state(progress)

      pair ->
        scope = quiz_scope(session["quiz_scope"])

        kind = quiz_kind_atom(quiz_kind)

        if scope == :learned and
             SifatAllah.key_id(pair, kind) not in progress["mastered_key_ids"] and
             is_nil(session["feedback"]) do
          default_state(progress)
        else
          default_state(progress)
          |> Map.merge(%{
            mode: :quiz,
            quiz_pair: pair,
            quiz_kind: kind,
            quiz_scope: scope,
            feedback: quiz_feedback(session["feedback"], pair, kind)
          })
        end
    end
  end

  defp restore_session(
         progress,
         %{"mode" => "review", "review_pair_id" => pair_id, "review_kind" => review_kind} =
           session
       )
       when review_kind in [
              "wajib_meaning",
              "wajib_opposite",
              "mustahil_meaning",
              "meaning_wajib",
              "mustahil_opposite",
              "meaning_mustahil",
              "meaning",
              "opposite",
              "opposite_meaning"
            ] do
    case SifatAllah.pair(pair_id) do
      nil ->
        default_state(progress)

      pair ->
        kind = quiz_kind_atom(review_kind)

        default_state(progress)
        |> Map.merge(%{
          mode: :review,
          review_pair: pair,
          review_kind: kind,
          feedback: review_feedback(session["feedback"], pair, kind)
        })
    end
  end

  defp restore_session(progress, %{"mode" => "dashboard"}), do: default_state(progress)
  defp restore_session(progress, _session), do: default_state(progress)

  defp pairs_from_ids(ids) do
    pairs = Enum.map(ids, &SifatAllah.pair/1)

    if ids != [] and length(ids) == length(Enum.uniq(ids)) and Enum.all?(pairs, & &1) do
      {:ok, pairs}
    else
      :error
    end
  end

  defp study_feedback("remembered", pair),
    do: %{kind: :success, text: "Hebat! Kamu sudah ingat #{pair.wajib}."}

  defp study_feedback(_feedback, _pair), do: nil

  defp quiz_feedback("success", _pair, _kind), do: %{kind: :success, text: "Betul!"}

  defp quiz_feedback("retry", pair, kind),
    do: retry_feedback("Nanti kita ulang lagi, ya.", pair, kind)

  defp quiz_feedback(_feedback, _pair, _kind), do: nil

  defp review_feedback("success", pair, _kind),
    do: %{kind: :success, text: "Mantap! #{pair.wajib} sudah kamu kuasai."}

  defp review_feedback("retry", pair, kind),
    do: retry_feedback("Coba sekali lagi, ya.", pair, kind)

  defp review_feedback(_feedback, _pair, _kind), do: nil

  defp retry_feedback(next_step, pair, kind) do
    %{
      kind: :retry,
      text:
        "Belum tepat. Jawaban yang benar: #{SifatAllah.correct_answer(pair, kind)}. #{next_step}"
    }
  end

  defp quiz_kind_atom("wajib_meaning"), do: :wajib_meaning
  defp quiz_kind_atom("wajib_opposite"), do: :wajib_opposite
  defp quiz_kind_atom("mustahil_meaning"), do: :mustahil_meaning
  defp quiz_kind_atom("meaning_wajib"), do: :meaning_wajib
  defp quiz_kind_atom("mustahil_opposite"), do: :mustahil_opposite
  defp quiz_kind_atom("meaning_mustahil"), do: :meaning_mustahil
  defp quiz_kind_atom("meaning"), do: :wajib_meaning
  defp quiz_kind_atom("opposite"), do: :wajib_opposite
  defp quiz_kind_atom("opposite_meaning"), do: :mustahil_meaning

  defp quiz_scope("learned"), do: :learned
  defp quiz_scope(_scope), do: :all

  defp record_quiz_answer(progress, pair, kind, correct?, _scope),
    do: SifatAllah.record_answer(progress, pair, kind, correct?)

  defp celebrate_if_correct(socket, true), do: push_event(socket, "sifat-celebrate", %{})
  defp celebrate_if_correct(socket, false), do: socket

  defp move_quiz_question(%{assigns: %{quiz_scope: :learned}} = socket, direction) do
    next_question =
      case direction do
        :next ->
          SifatAllah.next_mastered_question(
            socket.assigns.progress,
            socket.assigns.quiz_pair,
            socket.assigns.quiz_kind
          )

        :previous ->
          SifatAllah.previous_mastered_question(
            socket.assigns.progress,
            socket.assigns.quiz_pair,
            socket.assigns.quiz_kind
          )
      end

    case next_question do
      nil -> handle_event("dashboard", %{}, socket)
      {pair, kind} -> assign_quiz_question(socket, pair, kind)
    end
  end

  defp move_quiz_question(socket, direction) do
    kind =
      case direction do
        :next -> SifatAllah.next_question_kind(socket.assigns.quiz_kind)
        :previous -> SifatAllah.previous_question_kind(socket.assigns.quiz_kind)
      end

    pair = cycle_quiz_pair(socket.assigns, direction)
    assign_quiz_question(socket, pair, kind)
  end

  defp assign_quiz_question(socket, pair, kind) do
    {:noreply,
     socket
     |> cancel_auto_advance()
     |> assign(:quiz_pair, pair)
     |> assign(:quiz_kind, kind)
     |> assign(:feedback, nil)
     |> persist_snapshot()}
  end

  defp cycle_quiz_pair(%{quiz_scope: :all, progress: progress, quiz_pair: pair}, :next),
    do: SifatAllah.next_unlearned_pair(progress, pair)

  defp cycle_quiz_pair(%{quiz_scope: :all, progress: progress, quiz_pair: pair}, :previous),
    do: SifatAllah.previous_unlearned_pair(progress, pair)

  defp persist_snapshot(socket) do
    push_event(socket, "persist-sifat-allah", %{
      "version" => socket.assigns.progress["version"],
      "learned_ids" => socket.assigns.progress["learned_ids"],
      "review_ids" => socket.assigns.progress["review_ids"],
      "mastered_key_ids" => socket.assigns.progress["mastered_key_ids"],
      "review_key_ids" => socket.assigns.progress["review_key_ids"],
      "correct_answers" => socket.assigns.progress["correct_answers"],
      "incorrect_answers" => socket.assigns.progress["incorrect_answers"],
      "session" => session_snapshot(socket.assigns)
    })
  end

  defp push_history_entry(socket), do: push_event(socket, "sifat-history-entry", %{})

  defp cancel_auto_advance(socket),
    do: update(socket, :auto_advance_token, &(&1 + 1))

  defp schedule_auto_advance(socket, mode) do
    socket = cancel_auto_advance(socket)
    token = socket.assigns.auto_advance_token

    Process.send_after(self(), {:auto_advance, mode, token}, @quiz_auto_advance_delay)
    socket
  end

  defp session_snapshot(%{mode: :study} = assigns) do
    %{
      "mode" => "study",
      "lesson_ids" => Enum.map(assigns.lesson_pairs, & &1.id),
      "lesson_index" => assigns.lesson_index,
      "feedback" => if(assigns.feedback, do: "remembered", else: nil)
    }
  end

  defp session_snapshot(%{mode: :quiz} = assigns) do
    %{
      "mode" => "quiz",
      "quiz_pair_id" => assigns.quiz_pair.id,
      "quiz_kind" => Atom.to_string(assigns.quiz_kind),
      "quiz_scope" => Atom.to_string(assigns.quiz_scope),
      "feedback" => if(assigns.feedback, do: Atom.to_string(assigns.feedback.kind), else: nil)
    }
  end

  defp session_snapshot(%{mode: :review} = assigns) do
    %{
      "mode" => "review",
      "review_pair_id" => assigns.review_pair.id,
      "review_kind" => Atom.to_string(assigns.review_kind),
      "feedback" => if(assigns.feedback, do: Atom.to_string(assigns.feedback.kind), else: nil)
    }
  end

  defp session_snapshot(_assigns), do: %{"mode" => "dashboard"}
end
