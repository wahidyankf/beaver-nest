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

    progress = SifatAllah.record_answer(progress, qudrah, false)
    assert SifatAllah.review_pairs(progress) == [qudrah]

    progress = SifatAllah.record_answer(progress, qudrah, true)
    assert progress["review_ids"] == []
    assert SifatAllah.correct_count(progress) == 1
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

    assert progress["learned_ids"] == ["wujud"]
    assert SifatAllah.restore(%{}) == :error

    assert SifatAllah.restore(%{
             "version" => 1,
             "learned_ids" => ["not-a-pair"],
             "review_ids" => [],
             "correct_answers" => 0,
             "incorrect_answers" => 0
           }) == :error
  end

  test "offers a meaning or opposite quiz with a verifiable answer" do
    pair = hd(SifatAllah.curriculum())

    assert "Ada" in SifatAllah.answer_options(pair, :meaning)
    assert "‘Adam" in SifatAllah.answer_options(pair, :opposite)
    assert SifatAllah.correct_answer?(pair, :meaning, "Ada")
    refute SifatAllah.correct_answer?(pair, :opposite, "Hudus")
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

    assert Enum.map(SifatAllah.lesson_pairs(all_learned), & &1.wajib) == [
             "Wujud",
             "Qidam",
             "Baqa’"
           ]
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
