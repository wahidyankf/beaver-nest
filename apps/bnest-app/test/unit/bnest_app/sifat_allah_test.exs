defmodule BnestApp.SifatAllahTest do
  use ExUnit.Case, async: true

  alias BnestApp.SifatAllah

  test "ships the complete ordered curriculum" do
    curriculum = SifatAllah.curriculum()

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
    progress = SifatAllah.progress()
    qudrah = Enum.at(SifatAllah.curriculum(), 6)
    wujud = hd(SifatAllah.curriculum())

    progress = progress |> SifatAllah.remember(qudrah.id) |> SifatAllah.remember(wujud.id)
    assert progress["learned_ids"] == ["wujud", "qudrah"]
    assert SifatAllah.mastery_percent(progress) == 10

    progress = SifatAllah.forget(progress, wujud.id)
    assert progress["learned_ids"] == ["qudrah"]

    progress = SifatAllah.remember(progress, wujud.id)

    progress = SifatAllah.record_answer(progress, qudrah, false)
    assert SifatAllah.review_pairs(progress) == [qudrah]

    progress = SifatAllah.record_answer(progress, qudrah, true)
    assert progress["review_ids"] == []
    assert SifatAllah.correct_count(progress) == 1
  end

  test "tracks the 120 individual questions and moves an exact question between states" do
    wujud = hd(SifatAllah.curriculum())
    progress = SifatAllah.progress()

    assert SifatAllah.total_count() == 120
    assert SifatAllah.mastered_count(progress) == 0
    assert SifatAllah.unmastered_count(progress) == 120
    assert SifatAllah.mastery_percent(progress) == 0

    progress = SifatAllah.record_answer(progress, wujud, :wajib_meaning, true)

    assert progress["mastered_key_ids"] == ["wujud:wajib_meaning"]
    assert progress["learned_ids"] == []
    assert SifatAllah.mastered_count(progress) == 1
    assert SifatAllah.unmastered_count(progress) == 119
    assert SifatAllah.mastery_percent(progress) == 0

    progress = SifatAllah.record_answer(progress, wujud, :wajib_meaning, false)

    assert progress["mastered_key_ids"] == []
    assert progress["review_key_ids"] == ["wujud:wajib_meaning"]
    assert progress["review_ids"] == ["wujud"]
    assert SifatAllah.unmastered_count(progress) == 120

    progress =
      progress
      |> SifatAllah.record_answer(wujud, :wajib_meaning, true)
      |> SifatAllah.record_answer(wujud, :wajib_opposite, true)
      |> SifatAllah.record_answer(wujud, :mustahil_meaning, true)
      |> SifatAllah.record_answer(wujud, :meaning_wajib, true)
      |> SifatAllah.record_answer(wujud, :mustahil_opposite, true)
      |> SifatAllah.record_answer(wujud, :meaning_mustahil, true)

    assert progress["learned_ids"] == ["wujud"]
    assert SifatAllah.mastered_count(progress) == 6
    assert SifatAllah.unmastered_count(progress) == 114
    assert SifatAllah.mastery_percent(progress) == 5
  end

  test "uses exact question queues for learned and difficult review" do
    [wujud, qidam | _rest] = SifatAllah.curriculum()

    progress =
      SifatAllah.progress()
      |> SifatAllah.record_answer(wujud, :wajib_meaning, true)
      |> SifatAllah.record_answer(qidam, :wajib_opposite, false)

    assert SifatAllah.first_mastered_question(progress) == {wujud, :wajib_meaning}
    assert SifatAllah.first_review_question(progress) == {qidam, :wajib_opposite}

    assert SifatAllah.next_mastered_question(progress, wujud, :wajib_meaning) ==
             {wujud, :wajib_meaning}

    assert SifatAllah.next_review_question(progress, qidam, :wajib_opposite) ==
             {qidam, :wajib_opposite}

    progress = SifatAllah.record_answer(progress, qidam, :wajib_opposite, true)

    assert SifatAllah.first_review_question(progress) == nil
    assert SifatAllah.first_mastered_question(progress) == {wujud, :wajib_meaning}

    assert SifatAllah.next_mastered_question(progress, wujud, :wajib_meaning) ==
             {qidam, :wajib_opposite}
  end

  test "restores only valid versioned browser progress" do
    assert {:ok, progress} =
             SifatAllah.restore(%{
               "version" => 1,
               "learned_ids" => ["wujud"],
               "review_ids" => ["qudrah"],
               "correct_answers" => 2,
               "incorrect_answers" => 1
             })

    assert progress["learned_ids"] == []
    assert SifatAllah.mastered_count(progress) == 3
    assert SifatAllah.restore(%{}) == :error

    assert SifatAllah.restore(%{
             "version" => 1,
             "learned_ids" => ["not-a-pair"],
             "review_ids" => [],
             "correct_answers" => 0,
             "incorrect_answers" => 0
           }) == :error
  end

  test "restores persisted individual memory keys in a deterministic order" do
    assert {:ok, progress} =
             SifatAllah.restore(%{
               "version" => 1,
               "mastered_key_ids" => ["qidam:opposite", "wujud:meaning"],
               "review_key_ids" => ["wujud:opposite_meaning"],
               "correct_answers" => 2,
               "incorrect_answers" => 1
             })

    assert progress["mastered_key_ids"] == ["wujud:wajib_meaning", "qidam:wajib_opposite"]
    assert progress["review_key_ids"] == ["wujud:mustahil_meaning"]
    assert SifatAllah.mastered_count(progress) == 2
    assert SifatAllah.unmastered_count(progress) == 118
    assert SifatAllah.mastery_percent(progress) == 1
  end

  test "restores valid 120-question snapshots and rejects invalid question ids" do
    assert {:ok, progress} =
             SifatAllah.restore(%{
               "version" => 2,
               "mastered_key_ids" => ["qidam:meaning_wajib", "wujud:wajib_meaning"],
               "review_key_ids" => ["wujud:meaning_mustahil"],
               "correct_answers" => 2,
               "incorrect_answers" => 1
             })

    assert progress["mastered_key_ids"] == ["wujud:wajib_meaning", "qidam:meaning_wajib"]

    assert SifatAllah.restore(%{
             "version" => 2,
             "mastered_key_ids" => ["wujud:not-a-question"],
             "review_key_ids" => [],
             "correct_answers" => 0,
             "incorrect_answers" => 0
           }) == :error

    assert SifatAllah.restore(%{
             "version" => 1,
             "mastered_key_ids" => ["wujud:not-a-legacy-question"],
             "review_key_ids" => [],
             "correct_answers" => 0,
             "incorrect_answers" => 0
           }) == :error
  end

  test "offers each relation from both directions with a verifiable answer" do
    pair = hd(SifatAllah.curriculum())

    assert "Ada" in SifatAllah.answer_options(pair, :wajib_meaning)
    assert "Wujud" in SifatAllah.answer_options(pair, :meaning_wajib)
    assert "‘Adam" in SifatAllah.answer_options(pair, :wajib_opposite)
    assert "Wujud" in SifatAllah.answer_options(pair, :mustahil_opposite)
    assert "Tidak ada" in SifatAllah.answer_options(pair, :mustahil_meaning)
    assert "‘Adam" in SifatAllah.answer_options(pair, :meaning_mustahil)
    assert SifatAllah.question(pair, :mustahil_opposite) == "Apa lawan dari ‘Adam?"
    assert SifatAllah.question(pair, :meaning_wajib) == "Sifat wajib apa yang artinya Ada?"

    assert SifatAllah.question(pair, :meaning_mustahil) ==
             "Sifat mustahil apa yang artinya Tidak ada?"

    assert SifatAllah.correct_answer?(pair, :meaning_mustahil, "‘Adam")
    assert SifatAllah.next_question_kind(:mustahil_meaning) == :meaning_wajib
    assert SifatAllah.previous_question_kind(:wajib_meaning) == :meaning_mustahil
  end

  test "returns the correct answer for each quiz kind" do
    pair = hd(SifatAllah.curriculum())

    assert SifatAllah.correct_answer(pair, :wajib_meaning) == "Ada"
    assert SifatAllah.correct_answer(pair, :meaning_wajib) == "Wujud"
    assert SifatAllah.correct_answer(pair, :wajib_opposite) == "‘Adam"
    assert SifatAllah.correct_answer(pair, :mustahil_opposite) == "Wujud"
    assert SifatAllah.correct_answer(pair, :mustahil_meaning) == "Tidak ada"
    assert SifatAllah.correct_answer(pair, :meaning_mustahil) == "‘Adam"
  end

  test "places correct answers in varied, stable positions" do
    first = hd(SifatAllah.curriculum())
    second = SifatAllah.next_pair(first)

    first_position =
      Enum.find_index(SifatAllah.answer_options(first, :wajib_meaning), &(&1 == "Ada"))

    second_position =
      Enum.find_index(SifatAllah.answer_options(second, :wajib_opposite), &(&1 == "Hudus"))

    assert first_position != second_position

    assert SifatAllah.answer_options(first, :wajib_meaning) ==
             SifatAllah.answer_options(first, :wajib_meaning)
  end

  test "moves past pairs that are already remembered during a quiz" do
    progress =
      SifatAllah.progress() |> SifatAllah.remember("wujud") |> SifatAllah.remember("qidam")

    assert SifatAllah.next_unlearned_pair(progress, SifatAllah.pair("wujud")).id == "baqa"

    assert SifatAllah.previous_unlearned_pair(progress, SifatAllah.pair("wujud")).id ==
             "mutakalliman"

    all_remembered =
      Enum.reduce(SifatAllah.curriculum(), SifatAllah.progress(), fn pair, acc ->
        SifatAllah.remember(acc, pair.id)
      end)

    assert SifatAllah.next_unlearned_pair(all_remembered, List.last(SifatAllah.curriculum())).id ==
             "wujud"
  end

  test "skips remembered individual questions in an exam until every question is mastered" do
    [wujud, qidam | _rest] = SifatAllah.curriculum()

    progress = SifatAllah.record_answer(SifatAllah.progress(), wujud, :wajib_meaning, true)

    assert SifatAllah.first_exam_question(progress) == {qidam, :wajib_opposite}

    all_mastered =
      Enum.reduce(SifatAllah.curriculum(), SifatAllah.progress(), fn pair, acc ->
        SifatAllah.remember(acc, pair.id)
      end)

    assert SifatAllah.first_exam_question(all_mastered) == {wujud, :wajib_meaning}

    assert SifatAllah.next_exam_question(all_mastered, wujud, :wajib_meaning) ==
             {qidam, :wajib_opposite}
  end

  test "starts a short lesson with the first pairs not yet known" do
    progress = SifatAllah.progress() |> SifatAllah.remember("wujud")

    assert Enum.map(SifatAllah.lesson_pairs(progress), & &1.wajib) == [
             "Qidam",
             "Baqa’",
             "Mukhalafatuhu lil hawaditsi"
           ]

    all_learned =
      SifatAllah.curriculum()
      |> Enum.map(& &1.id)
      |> Enum.reduce(SifatAllah.progress(), &SifatAllah.remember(&2, &1))

    assert SifatAllah.lesson_pairs(all_learned) == []
    assert SifatAllah.quiz_pair(all_learned).wajib == "Wujud"
  end

  test "moves through the curriculum and wraps after the final pair" do
    curriculum = SifatAllah.curriculum()

    assert SifatAllah.next_pair(hd(curriculum)).wajib == "Qidam"
    assert SifatAllah.next_pair(List.last(curriculum)).wajib == "Wujud"
    assert SifatAllah.next_pair(%{id: "unknown"}).wajib == "Wujud"

    assert SifatAllah.previous_pair(hd(curriculum)).wajib == "Mutakalliman"
    assert SifatAllah.previous_pair(Enum.at(curriculum, 1)).wajib == "Wujud"
    assert SifatAllah.previous_pair(%{id: "unknown"}).wajib == "Mutakalliman"
  end

  test "moves a focused review to another difficult pair before repeating" do
    [wujud, qidam | _rest] = SifatAllah.curriculum()

    progress =
      SifatAllah.progress()
      |> SifatAllah.record_answer(wujud, false)
      |> SifatAllah.record_answer(qidam, false)

    assert SifatAllah.next_review_pair(progress, wujud) == qidam
    assert SifatAllah.next_review_pair(progress, qidam) == wujud
    assert SifatAllah.next_review_pair(progress, %{id: "unknown"}) == wujud
    assert SifatAllah.next_review_pair(SifatAllah.progress(), wujud) == nil
  end

  test "finds a curriculum pair only for a known id" do
    assert SifatAllah.pair("qidam").wajib == "Qidam"
    assert SifatAllah.pair("unknown") == nil
    assert SifatAllah.pair(nil) == nil
  end
end
