defmodule BnestAppWeb.SifatAllahLive do
  use BnestAppWeb, :live_view

  alias BnestApp.SifatAllah

  @max_snapshot_bytes 10_000

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

    {:noreply,
     socket
     |> assign(:mode, :study)
     |> assign(:lesson_pairs, lesson_pairs)
     |> assign(:lesson_index, 0)
     |> assign(:feedback, nil)
     |> persist_snapshot()}
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
     |> assign(:mode, :quiz)
     |> assign(:quiz_pair, SifatAllah.quiz_pair(socket.assigns.progress))
     |> assign(:quiz_kind, :meaning)
     |> assign(:feedback, nil)
     |> persist_snapshot()}
  end

  def handle_event("start-review", _params, socket) do
    case SifatAllah.review_pairs(socket.assigns.progress) do
      [] ->
        {:noreply, socket}

      [pair | _rest] ->
        {:noreply,
         socket
         |> assign(:mode, :review)
         |> assign(:review_pair, pair)
         |> assign(:review_kind, :meaning)
         |> assign(:feedback, nil)
         |> persist_snapshot()}
    end
  end

  def handle_event("answer", %{"answer" => answer}, socket) do
    pair = socket.assigns.quiz_pair
    correct? = SifatAllah.correct_answer?(pair, socket.assigns.quiz_kind, answer)
    progress = SifatAllah.record_answer(socket.assigns.progress, pair, correct?)

    feedback =
      if correct? do
        %{kind: :success, text: "Betul!"}
      else
        %{kind: :retry, text: "Belum tepat. Nanti kita ulang lagi, ya."}
      end

    {:noreply,
     socket
     |> assign(:progress, progress)
     |> assign(:feedback, feedback)
     |> persist_snapshot()}
  end

  def handle_event("review-answer", %{"answer" => answer}, socket) do
    pair = socket.assigns.review_pair
    correct? = SifatAllah.correct_answer?(pair, socket.assigns.review_kind, answer)
    progress = SifatAllah.record_answer(socket.assigns.progress, pair, correct?)

    feedback =
      if correct? do
        %{kind: :success, text: "Mantap! #{pair.wajib} sudah kamu kuasai."}
      else
        %{kind: :retry, text: "Belum tepat. Coba sekali lagi, ya."}
      end

    {:noreply,
     socket
     |> assign(:progress, progress)
     |> assign(:feedback, feedback)
     |> persist_snapshot()}
  end

  def handle_event("next-question", _params, socket) do
    quiz_kind = if socket.assigns.quiz_kind == :meaning, do: :opposite, else: :meaning

    {:noreply,
     socket
     |> assign(:quiz_pair, SifatAllah.next_pair(socket.assigns.quiz_pair))
     |> assign(:quiz_kind, quiz_kind)
     |> assign(:feedback, nil)
     |> persist_snapshot()}
  end

  def handle_event("previous-question", _params, socket) do
    quiz_kind = if socket.assigns.quiz_kind == :meaning, do: :opposite, else: :meaning

    {:noreply,
     socket
     |> assign(:quiz_pair, SifatAllah.previous_pair(socket.assigns.quiz_pair))
     |> assign(:quiz_kind, quiz_kind)
     |> assign(:feedback, nil)
     |> persist_snapshot()}
  end

  def handle_event("next-review-question", _params, socket) do
    case SifatAllah.next_review_pair(socket.assigns.progress, socket.assigns.review_pair) do
      nil ->
        handle_event("dashboard", %{}, socket)

      pair ->
        review_kind =
          next_review_kind(socket.assigns.review_pair, pair, socket.assigns.review_kind)

        {:noreply,
         socket
         |> assign(:review_pair, pair)
         |> assign(:review_kind, review_kind)
         |> assign(:feedback, nil)
         |> persist_snapshot()}
    end
  end

  def handle_event("dashboard", _params, socket) do
    {:noreply,
     socket |> assign(:mode, :dashboard) |> assign(:feedback, nil) |> persist_snapshot()}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="sifat-shell">
      <header class="sifat-topbar">
        <a href="/" class="sifat-home-link">← Beaver Nest</a>
        <p class="sifat-saved-note">Tersimpan di browser ini</p>
      </header>

      <section class="sifat-stage" aria-labelledby="sifat-title">
        <div class="sifat-title-card">
          <p class="sifat-kicker">MISI UJIAN BESOK</p>
          <h1 id="sifat-title">Misi Hafal 40 Sifat Allah</h1>
          <p>20 pasangan untuk kamu hafal</p>
        </div>

        <section class="sifat-progress" aria-label="Kemajuan hafalan">
          <div>
            <span>Sudah kenal</span>
            <strong data-testid="sifat-allah-progress">
              {SifatAllah.learned_count(@progress)} dari 20 pasangan sudah kenal
            </strong>
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
    </main>
    """
  end

  attr(:progress, :map, required: true)

  defp dashboard(assigns) do
    ~H"""
    <section class="sifat-dashboard" aria-label="Pilih latihan">
      <p class="sifat-instruction">
        Pilih satu langkah kecil. Kamu nggak perlu hafal semuanya sekaligus.
      </p>
      <div class="sifat-actions">
        <button type="button" class="sifat-primary-action" phx-click="start-learning">
          <span aria-hidden="true">◎</span>
          <strong>Belajar 3 Pasangan</strong>
          <small>Lihat, baca, lalu ingat</small>
        </button>
        <button type="button" class="sifat-secondary-action" phx-click="start-quiz">
          <span aria-hidden="true">✦</span>
          <strong>Latihan Ujian</strong>
          <small>Tebak arti atau lawannya</small>
        </button>
      </div>
      <button
        type="button"
        class="sifat-review-action"
        phx-click="start-review"
        disabled={@progress["review_ids"] == []}
      >
        Ulangi yang masih bikin bingung ({length(@progress["review_ids"])})
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
        <div class="sifat-side sifat-wajib-side">
          <span>SIFAT WAJIB</span>
          <strong>{@pair.wajib}</strong>
          <p>{@pair.wajib_meaning}</p>
        </div>
        <div class="sifat-pair-arrow" aria-hidden="true">↔</div>
        <div class="sifat-side sifat-mustahil-side">
          <span>SIFAT MUSTAHIL</span>
          <strong>{@pair.mustahil}</strong>
          <p>{@pair.mustahil_meaning}</p>
        </div>
      </article>
      <p class="sifat-swipe-hint" aria-hidden="true">
        Geser kanan untuk kembali <span>·</span> geser kiri untuk lanjut
      </p>
      <p :if={@assigns.feedback} class={"sifat-feedback is-#{@assigns.feedback.kind}"} role="status">
        {@assigns.feedback.text}
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
        <button type="button" class="sifat-quiet-action" phx-click="dashboard">← Kembali ke misi</button>
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

    question =
      if assigns.assigns.quiz_kind == :meaning,
        do: "Apa arti #{pair.wajib}?",
        else: "Apa lawan dari #{pair.wajib}?"

    options = SifatAllah.answer_options(pair, assigns.assigns.quiz_kind)
    revision_pairs = SifatAllah.review_pairs(assigns.assigns.progress)

    assigns =
      assign(assigns,
        pair: pair,
        question: question,
        options: options,
        revision_pairs: revision_pairs
      )

    ~H"""
    <section class="sifat-quiz" aria-label="Latihan ujian">
      <p class="sifat-step">SOAL LATIHAN</p>
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
      <button type="button" class="sifat-quiet-action" phx-click="dashboard">← Kembali ke misi</button>
    </section>
    """
  end

  attr(:assigns, :map, required: true)

  defp review(assigns) do
    pair = assigns.assigns.review_pair

    question =
      if assigns.assigns.review_kind == :meaning,
        do: "Apa arti #{pair.wajib}?",
        else: "Apa lawan dari #{pair.wajib}?"

    options = SifatAllah.answer_options(pair, assigns.assigns.review_kind)
    remaining_count = length(assigns.assigns.progress["review_ids"])

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
      <p class="sifat-review-count">Masih ada {@remaining_count} pasangan untuk dikuasai</p>
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
      <button type="button" class="sifat-quiet-action" phx-click="dashboard">← Kembali ke misi</button>
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
      quiz_kind: :meaning,
      review_pair: nil,
      review_kind: :meaning,
      feedback: nil
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
       when quiz_kind in ["meaning", "opposite"] do
    case SifatAllah.pair(pair_id) do
      nil ->
        default_state(progress)

      pair ->
        default_state(progress)
        |> Map.merge(%{
          mode: :quiz,
          quiz_pair: pair,
          quiz_kind: quiz_kind_atom(quiz_kind),
          feedback: quiz_feedback(session["feedback"])
        })
    end
  end

  defp restore_session(
         progress,
         %{"mode" => "review", "review_pair_id" => pair_id, "review_kind" => review_kind} =
           session
       )
       when review_kind in ["meaning", "opposite"] do
    case SifatAllah.pair(pair_id) do
      nil ->
        default_state(progress)

      pair ->
        default_state(progress)
        |> Map.merge(%{
          mode: :review,
          review_pair: pair,
          review_kind: quiz_kind_atom(review_kind),
          feedback: review_feedback(session["feedback"], pair)
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

  defp quiz_feedback("success"), do: %{kind: :success, text: "Betul!"}

  defp quiz_feedback("retry"),
    do: %{kind: :retry, text: "Belum tepat. Nanti kita ulang lagi, ya."}

  defp quiz_feedback(_feedback), do: nil

  defp review_feedback("success", pair),
    do: %{kind: :success, text: "Mantap! #{pair.wajib} sudah kamu kuasai."}

  defp review_feedback("retry", _pair),
    do: %{kind: :retry, text: "Belum tepat. Coba sekali lagi, ya."}

  defp review_feedback(_feedback, _pair), do: nil

  defp quiz_kind_atom("meaning"), do: :meaning
  defp quiz_kind_atom("opposite"), do: :opposite

  defp next_review_kind(%{id: id}, %{id: id}, kind), do: kind
  defp next_review_kind(_current_pair, _next_pair, :meaning), do: :opposite
  defp next_review_kind(_current_pair, _next_pair, :opposite), do: :meaning

  defp persist_snapshot(socket) do
    push_event(socket, "persist-sifat-allah", %{
      "version" => socket.assigns.progress["version"],
      "learned_ids" => socket.assigns.progress["learned_ids"],
      "review_ids" => socket.assigns.progress["review_ids"],
      "correct_answers" => socket.assigns.progress["correct_answers"],
      "incorrect_answers" => socket.assigns.progress["incorrect_answers"],
      "session" => session_snapshot(socket.assigns)
    })
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
