defmodule BnestApp.SifatAllah.Domain.QuizTest do
  use ExUnit.Case, async: true

  alias BnestApp.SifatAllah.Domain.Quiz

  test "ships the complete ordered curriculum" do
    curriculum = Quiz.curriculum()

    assert length(curriculum) == 20

    assert hd(curriculum) == %{
             id: "wujud",
             wajib: "Wujud",
             wajib_meaning: "Ada",
             mustahil: "‘Adam",
             mustahil_meaning: "Tidak ada"
           }

    assert List.last(curriculum).wajib == "Mutakalliman"
  end

  test "keeps learned and review ids in curriculum order" do
    progress = Quiz.progress()
    qudrah = Enum.at(Quiz.curriculum(), 6)
    wujud = hd(Quiz.curriculum())

    progress = progress |> Quiz.remember(qudrah.id) |> Quiz.remember(wujud.id)
    assert progress["learned_ids"] == ["wujud", "qudrah"]
    assert Quiz.mastery_percent(progress) == 10

    progress = Quiz.forget(progress, wujud.id)
    assert progress["learned_ids"] == ["qudrah"]

    progress = Quiz.remember(progress, wujud.id)

    progress = Quiz.record_answer(progress, qudrah, false)
    assert Quiz.review_pairs(progress) == [qudrah]

    progress = Quiz.record_answer(progress, qudrah, true)
    assert progress["review_ids"] == []
    assert Quiz.correct_count(progress) == 1
  end

  test "tracks the 120 individual questions and moves an exact question between states" do
    wujud = hd(Quiz.curriculum())
    progress = Quiz.progress()

    assert Quiz.total_count() == 120
    assert Quiz.mastered_count(progress) == 0
    assert Quiz.unmastered_count(progress) == 120
    assert Quiz.mastery_percent(progress) == 0

    progress = Quiz.record_answer(progress, wujud, :wajib_meaning, true)

    assert progress["mastered_key_ids"] == ["wujud:wajib_meaning"]
    assert progress["learned_ids"] == []
    assert Quiz.mastered_count(progress) == 1
    assert Quiz.unmastered_count(progress) == 119
    assert Quiz.mastery_percent(progress) == 0

    progress = Quiz.record_answer(progress, wujud, :wajib_meaning, false)

    assert progress["mastered_key_ids"] == []
    assert progress["review_key_ids"] == ["wujud:wajib_meaning"]
    assert progress["review_ids"] == ["wujud"]
    assert Quiz.mastered_count(progress) == 0
    assert Quiz.unmastered_count(progress) == 120
    assert Quiz.mastery_percent(progress) == 0

    progress =
      progress
      |> Quiz.record_answer(wujud, :wajib_meaning, true)
      |> Quiz.record_answer(wujud, :wajib_opposite, true)
      |> Quiz.record_answer(wujud, :mustahil_meaning, true)
      |> Quiz.record_answer(wujud, :meaning_wajib, true)
      |> Quiz.record_answer(wujud, :mustahil_opposite, true)
      |> Quiz.record_answer(wujud, :meaning_mustahil, true)

    assert progress["learned_ids"] == ["wujud"]
    assert Quiz.mastered_count(progress) == 6
    assert Quiz.unmastered_count(progress) == 114
    assert Quiz.mastery_percent(progress) == 5
  end

  test "uses exact question queues for learned and difficult review" do
    [wujud, qidam | _rest] = Quiz.curriculum()

    progress =
      Quiz.progress()
      |> Quiz.record_answer(wujud, :wajib_meaning, true)
      |> Quiz.record_answer(qidam, :wajib_opposite, false)

    assert Quiz.first_mastered_question(progress) == {wujud, :wajib_meaning}
    assert Quiz.first_review_question(progress) == {qidam, :wajib_opposite}

    assert Quiz.next_mastered_question(progress, wujud, :wajib_meaning) ==
             {wujud, :wajib_meaning}

    assert Quiz.next_review_question(progress, qidam, :wajib_opposite) ==
             {qidam, :wajib_opposite}

    progress = Quiz.record_answer(progress, qidam, :wajib_opposite, true)

    assert Quiz.first_review_question(progress) == nil
    assert Quiz.first_mastered_question(progress) == {wujud, :wajib_meaning}

    assert Quiz.next_mastered_question(progress, wujud, :wajib_meaning) ==
             {qidam, :wajib_opposite}
  end

  test "restores only valid versioned browser progress" do
    assert {:ok, progress} =
             Quiz.restore(%{
               "version" => 1,
               "learned_ids" => ["wujud"],
               "review_ids" => ["qudrah"],
               "correct_answers" => 2,
               "incorrect_answers" => 1
             })

    assert progress["learned_ids"] == []
    assert Quiz.mastered_count(progress) == 3
    assert Quiz.restore(%{}) == :error

    assert Quiz.restore(%{
             "version" => 1,
             "learned_ids" => ["not-a-pair"],
             "review_ids" => [],
             "correct_answers" => 0,
             "incorrect_answers" => 0
           }) == :error
  end

  test "restores persisted individual memory keys in a deterministic order" do
    assert {:ok, progress} =
             Quiz.restore(%{
               "version" => 1,
               "mastered_key_ids" => ["qidam:opposite", "wujud:meaning"],
               "review_key_ids" => ["wujud:opposite_meaning"],
               "correct_answers" => 2,
               "incorrect_answers" => 1
             })

    assert progress["mastered_key_ids"] == ["wujud:wajib_meaning", "qidam:wajib_opposite"]
    assert progress["review_key_ids"] == ["wujud:mustahil_meaning"]
    assert Quiz.mastered_count(progress) == 2
    assert Quiz.unmastered_count(progress) == 118
    assert Quiz.mastery_percent(progress) == 1
  end

  test "restores valid 120-question snapshots and rejects invalid question ids" do
    assert {:ok, progress} =
             Quiz.restore(%{
               "version" => 2,
               "mastered_key_ids" => ["qidam:meaning_wajib", "wujud:wajib_meaning"],
               "review_key_ids" => ["wujud:meaning_mustahil"],
               "correct_answers" => 2,
               "incorrect_answers" => 1
             })

    assert progress["mastered_key_ids"] == ["wujud:wajib_meaning", "qidam:meaning_wajib"]
    assert progress["version"] == 2

    assert Quiz.restore(%{
             "version" => 2,
             "mastered_key_ids" => ["wujud:not-a-question"],
             "review_key_ids" => [],
             "correct_answers" => 0,
             "incorrect_answers" => 0
           }) == :error

    assert Quiz.restore(%{
             "version" => 1,
             "mastered_key_ids" => ["wujud:not-a-legacy-question"],
             "review_key_ids" => [],
             "correct_answers" => 0,
             "incorrect_answers" => 0
           }) == :error
  end

  test "offers each relation from both directions with a verifiable answer" do
    pair = hd(Quiz.curriculum())

    assert "Ada" in Quiz.answer_options(pair, :wajib_meaning)
    assert "Wujud" in Quiz.answer_options(pair, :meaning_wajib)
    assert "‘Adam" in Quiz.answer_options(pair, :wajib_opposite)
    assert "Wujud" in Quiz.answer_options(pair, :mustahil_opposite)
    assert "Tidak ada" in Quiz.answer_options(pair, :mustahil_meaning)
    assert "‘Adam" in Quiz.answer_options(pair, :meaning_mustahil)
    assert Quiz.question(pair, :mustahil_opposite) == "Apa lawan dari ‘Adam?"
    assert Quiz.question(pair, :meaning_wajib) == "Sifat wajib apa yang artinya Ada?"

    assert Quiz.question(pair, :meaning_mustahil) ==
             "Sifat mustahil apa yang artinya Tidak ada?"

    assert Quiz.correct_answer?(pair, :meaning_mustahil, "‘Adam")
    assert Quiz.next_question_kind(:mustahil_meaning) == :meaning_wajib
    assert Quiz.previous_question_kind(:wajib_meaning) == :meaning_mustahil
  end

  test "returns the correct answer for each quiz kind" do
    pair = hd(Quiz.curriculum())

    assert Quiz.correct_answer(pair, :wajib_meaning) == "Ada"
    assert Quiz.correct_answer(pair, :meaning_wajib) == "Wujud"
    assert Quiz.correct_answer(pair, :wajib_opposite) == "‘Adam"
    assert Quiz.correct_answer(pair, :mustahil_opposite) == "Wujud"
    assert Quiz.correct_answer(pair, :mustahil_meaning) == "Tidak ada"
    assert Quiz.correct_answer(pair, :meaning_mustahil) == "‘Adam"
  end

  test "places correct answers in varied, stable positions" do
    first = hd(Quiz.curriculum())
    second = Quiz.next_pair(first)

    first_position =
      Enum.find_index(Quiz.answer_options(first, :wajib_meaning), &(&1 == "Ada"))

    second_position =
      Enum.find_index(Quiz.answer_options(second, :wajib_opposite), &(&1 == "Hudus"))

    assert first_position != second_position

    assert Quiz.answer_options(first, :wajib_meaning) ==
             Quiz.answer_options(first, :wajib_meaning)
  end

  test "moves past pairs that are already remembered during a quiz" do
    progress =
      Quiz.progress() |> Quiz.remember("wujud") |> Quiz.remember("qidam")

    assert Quiz.next_unlearned_pair(progress, Quiz.pair("wujud")).id == "baqa"

    assert Quiz.previous_unlearned_pair(progress, Quiz.pair("wujud")).id ==
             "mutakalliman"

    all_remembered =
      Enum.reduce(Quiz.curriculum(), Quiz.progress(), fn pair, acc ->
        Quiz.remember(acc, pair.id)
      end)

    assert Quiz.next_unlearned_pair(all_remembered, List.last(Quiz.curriculum())).id ==
             "wujud"
  end

  test "skips remembered individual questions in an exam until every question is mastered" do
    [wujud, qidam | _rest] = Quiz.curriculum()

    progress = Quiz.record_answer(Quiz.progress(), wujud, :wajib_meaning, true)

    assert Quiz.first_exam_question(progress) == {qidam, :wajib_opposite}

    all_mastered =
      Enum.reduce(Quiz.curriculum(), Quiz.progress(), fn pair, acc ->
        Quiz.remember(acc, pair.id)
      end)

    assert Quiz.first_exam_question(all_mastered) == {wujud, :wajib_meaning}

    assert Quiz.next_exam_question(all_mastered, wujud, :wajib_meaning) ==
             {qidam, :wajib_opposite}
  end

  test "starts a short lesson with the first pairs not yet known" do
    progress = Quiz.progress() |> Quiz.remember("wujud")

    assert Enum.map(Quiz.lesson_pairs(progress), & &1.wajib) == [
             "Qidam",
             "Baqa’",
             "Mukhalafatuhu lil hawaditsi"
           ]

    all_learned =
      Quiz.curriculum()
      |> Enum.map(& &1.id)
      |> Enum.reduce(Quiz.progress(), &Quiz.remember(&2, &1))

    assert Quiz.lesson_pairs(all_learned) == []
    assert Quiz.quiz_pair(all_learned).wajib == "Wujud"
  end

  test "moves through the curriculum and wraps after the final pair" do
    curriculum = Quiz.curriculum()

    assert Quiz.next_pair(hd(curriculum)).wajib == "Qidam"
    assert Quiz.next_pair(List.last(curriculum)).wajib == "Wujud"
    assert Quiz.next_pair(%{id: "unknown"}).wajib == "Wujud"

    assert Quiz.previous_pair(hd(curriculum)).wajib == "Mutakalliman"
    assert Quiz.previous_pair(Enum.at(curriculum, 1)).wajib == "Wujud"
    assert Quiz.previous_pair(%{id: "unknown"}).wajib == "Mutakalliman"
  end

  test "moves a focused review to another difficult pair before repeating" do
    [wujud, qidam | _rest] = Quiz.curriculum()

    progress =
      Quiz.progress()
      |> Quiz.record_answer(wujud, false)
      |> Quiz.record_answer(qidam, false)

    assert Quiz.next_review_pair(progress, wujud) == qidam
    assert Quiz.next_review_pair(progress, qidam) == wujud
    assert Quiz.next_review_pair(progress, %{id: "unknown"}) == wujud
    assert Quiz.next_review_pair(Quiz.progress(), wujud) == nil
  end

  test "finds a curriculum pair only for a known id" do
    assert Quiz.pair("qidam").wajib == "Qidam"
    assert Quiz.pair("unknown") == nil
    assert Quiz.pair(nil) == nil
  end
end
