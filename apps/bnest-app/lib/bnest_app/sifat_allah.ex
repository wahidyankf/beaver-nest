defmodule BnestApp.SifatAllah do
  @moduledoc false

  @progress_version 1
  @question_kinds [:meaning, :opposite, :opposite_meaning]

  @curriculum [
                {"wujud", "Wujud", "Ada", "‘Adam", "Tidak ada"},
                {"qidam", "Qidam", "Dahulu", "Hudus", "Baru"},
                {"baqa", "Baqa’", "Kekal", "Fana’", "Binasa"},
                {
                  "mukhalafatuhu-lil-hawaditsi",
                  "Mukhalafatuhu lil hawaditsi",
                  "Berbeda dengan makhluk",
                  "Mumatsalatuhu lil hawaditsi",
                  "Sama dengan makhluk"
                },
                {
                  "qiyamuhu-binafsihi",
                  "Qiyamuhu binafsihi",
                  "Berdiri sendiri",
                  "Qiyamuhu bighairihi",
                  "Membutuhkan pihak lain"
                },
                {"wahdaniyah", "Wahdaniyah", "Esa", "Ta’addud", "Berbilang"},
                {"qudrah", "Qudrah", "Berkuasa", "‘Ajzun", "Lemah"},
                {"iradah", "Iradah", "Berkehendak", "Karahah", "Terpaksa"},
                {"ilmun", "Ilmun", "Mengetahui", "Jahlun", "Bodoh"},
                {"hayah", "Hayah", "Hidup", "Mautun", "Mati"},
                {"sama", "Sama’", "Mendengar", "Summun", "Tuli"},
                {"basar", "Basar", "Melihat", "‘Umyun", "Buta"},
                {"kalam", "Kalam", "Berfirman", "Bukmun", "Bisu"},
                {"qadiran", "Qadiran", "Allah Maha Berkuasa", "‘Ajizan", "Keadaannya lemah"},
                {
                  "muridan",
                  "Muridan",
                  "Allah Maha Berkehendak",
                  "Karihan",
                  "Keadaannya terpaksa"
                },
                {"aliman", "‘Aliman", "Allah Maha Mengetahui", "Jahilan", "Keadaannya bodoh"},
                {"hayyan", "Hayyan", "Allah Mahahidup", "Mayyitan", "Keadaannya mati"},
                {"samian", "Sami’an", "Allah Maha Mendengar", "Asamma", "Keadaannya tuli"},
                {"basiran", "Basiran", "Allah Maha Melihat", "A’ma", "Keadaannya buta"},
                {
                  "mutakalliman",
                  "Mutakalliman",
                  "Allah Maha Berfirman",
                  "Abkama",
                  "Keadaannya bisu"
                }
              ]
              |> Enum.map(fn {id, wajib, wajib_meaning, mustahil, mustahil_meaning} ->
                %{
                  id: id,
                  wajib: wajib,
                  wajib_meaning: wajib_meaning,
                  mustahil: mustahil,
                  mustahil_meaning: mustahil_meaning
                }
              end)

  @spec curriculum() :: [map()]
  def curriculum, do: @curriculum

  @spec progress() :: map()
  def progress do
    %{
      "version" => @progress_version,
      "learned_ids" => [],
      "review_ids" => [],
      "mastered_key_ids" => [],
      "review_key_ids" => [],
      "correct_answers" => 0,
      "incorrect_answers" => 0
    }
  end

  @spec restore(map()) :: {:ok, map()} | :error
  def restore(%{
        "version" => @progress_version,
        "mastered_key_ids" => mastered_key_ids,
        "review_key_ids" => review_key_ids,
        "correct_answers" => correct_answers,
        "incorrect_answers" => incorrect_answers
      })
      when is_list(mastered_key_ids) and is_list(review_key_ids) and is_integer(correct_answers) and
             correct_answers >= 0 and is_integer(incorrect_answers) and incorrect_answers >= 0 do
    with true <- valid_key_ids?(mastered_key_ids), true <- valid_key_ids?(review_key_ids) do
      {:ok,
       progress_from_keys(mastered_key_ids, review_key_ids, correct_answers, incorrect_answers)}
    else
      false -> :error
    end
  end

  def restore(%{
        "version" => @progress_version,
        "learned_ids" => learned_ids,
        "review_ids" => review_ids,
        "correct_answers" => correct_answers,
        "incorrect_answers" => incorrect_answers
      })
      when is_list(learned_ids) and is_list(review_ids) and is_integer(correct_answers) and
             correct_answers >= 0 and is_integer(incorrect_answers) and incorrect_answers >= 0 do
    with true <- valid_ids?(learned_ids),
         true <- valid_ids?(review_ids) do
      {:ok,
       progress_from_keys(
         Enum.flat_map(ordered_ids(learned_ids), &pair_key_ids/1),
         Enum.flat_map(ordered_ids(review_ids), &pair_key_ids/1),
         correct_answers,
         incorrect_answers
       )}
    else
      false -> :error
    end
  end

  def restore(_snapshot), do: :error

  @spec remember(map(), String.t()) :: map()
  def remember(progress, id) do
    update_key_progress(progress, pair_key_ids(id), [], 0, 0)
  end

  @spec forget(map(), String.t()) :: map()
  def forget(progress, id) do
    update_key_progress(progress, [], pair_key_ids(id), 0, 0)
  end

  @spec record_answer(map(), map(), boolean()) :: map()
  def record_answer(progress, pair, true) do
    remember(progress, pair.id)
    |> Map.update!("correct_answers", &(&1 + 1))
  end

  def record_answer(progress, pair, false) do
    forget(progress, pair.id)
    |> Map.update!("incorrect_answers", &(&1 + 1))
  end

  @spec record_answer(map(), map(), :meaning | :opposite | :opposite_meaning, boolean()) :: map()
  def record_answer(progress, pair, kind, true) do
    update_key_progress(progress, [key_id(pair, kind)], [], 1, 0)
  end

  def record_answer(progress, pair, kind, false) do
    update_key_progress(progress, [], [key_id(pair, kind)], 0, 1)
  end

  @spec learned_count(map()) :: non_neg_integer()
  def learned_count(progress), do: length(progress["learned_ids"])

  @spec total_count() :: pos_integer()
  def total_count, do: length(@curriculum) * length(@question_kinds)

  @spec mastered_count(map()) :: non_neg_integer()
  def mastered_count(progress), do: length(progress["mastered_key_ids"])

  @spec unmastered_count(map()) :: non_neg_integer()
  def unmastered_count(progress), do: total_count() - mastered_count(progress)

  @spec mastery_percent(map()) :: 0..100
  def mastery_percent(progress), do: div(mastered_count(progress) * 100, total_count())

  @spec correct_count(map()) :: non_neg_integer()
  def correct_count(progress), do: progress["correct_answers"]

  @spec lesson_pairs(map()) :: [map()]
  def lesson_pairs(progress) do
    progress
    |> unlearned_pairs()
    |> Enum.take(3)
  end

  @spec unlearned_pairs(map()) :: [map()]
  def unlearned_pairs(progress) do
    learned_ids = MapSet.new(progress["learned_ids"])
    Enum.reject(@curriculum, &MapSet.member?(learned_ids, &1.id))
  end

  @spec next_unlearned_pair(map(), map()) :: map()
  def next_unlearned_pair(progress, pair), do: cycle_quiz_pairs(progress, pair, :next)

  @spec previous_unlearned_pair(map(), map()) :: map()
  def previous_unlearned_pair(progress, pair), do: cycle_quiz_pairs(progress, pair, :previous)

  @spec review_pairs(map()) :: [map()]
  def review_pairs(progress), do: pairs_for(progress["review_ids"])

  @spec next_review_pair(map(), map()) :: map() | nil
  def next_review_pair(progress, pair) do
    review_ids = MapSet.new(progress["review_ids"])

    case Enum.find_index(@curriculum, &(&1.id == pair.id)) do
      nil ->
        Enum.find(@curriculum, &MapSet.member?(review_ids, &1.id))

      index ->
        @curriculum
        |> Enum.drop(index + 1)
        |> Kernel.++(Enum.take(@curriculum, index + 1))
        |> Enum.find(&MapSet.member?(review_ids, &1.id))
    end
  end

  @spec quiz_pair(map()) :: map()
  def quiz_pair(progress) do
    case unlearned_pairs(progress) do
      [] -> hd(@curriculum)
      [pair | _rest] -> pair
    end
  end

  @spec next_pair(map()) :: map()
  def next_pair(pair) do
    case Enum.find_index(@curriculum, &(&1.id == pair.id)) do
      nil -> hd(@curriculum)
      index -> Enum.at(@curriculum, rem(index + 1, length(@curriculum)))
    end
  end

  @spec previous_pair(map()) :: map()
  def previous_pair(pair) do
    case Enum.find_index(@curriculum, &(&1.id == pair.id)) do
      nil -> List.last(@curriculum)
      0 -> List.last(@curriculum)
      index -> Enum.at(@curriculum, index - 1)
    end
  end

  @spec pair(String.t()) :: map() | nil
  def pair(id) when is_binary(id), do: Enum.find(@curriculum, &(&1.id == id))
  def pair(_id), do: nil

  @spec question(map(), :meaning | :opposite | :opposite_meaning) :: String.t()
  def question(pair, :meaning), do: "Apa arti #{pair.wajib}?"
  def question(pair, :opposite), do: "Apa lawan dari #{pair.wajib}?"
  def question(pair, :opposite_meaning), do: "Apa arti #{pair.mustahil}?"

  @spec answer_options(map(), :meaning | :opposite | :opposite_meaning) :: [String.t()]
  def answer_options(pair, :meaning) do
    arrange_answer_options(pair, :meaning, [pair.wajib_meaning, "Dahulu", "Kekal", "Lemah"])
  end

  def answer_options(pair, :opposite) do
    arrange_answer_options(pair, :opposite, [pair.mustahil, "Hudus", "Fana’", "‘Ajzun"])
  end

  def answer_options(pair, :opposite_meaning) do
    arrange_answer_options(pair, :opposite_meaning, [
      pair.mustahil_meaning,
      "Baru",
      "Binasa",
      "Lemah"
    ])
  end

  @spec correct_answer(map(), :meaning | :opposite | :opposite_meaning) :: String.t()
  def correct_answer(pair, :meaning), do: pair.wajib_meaning
  def correct_answer(pair, :opposite), do: pair.mustahil
  def correct_answer(pair, :opposite_meaning), do: pair.mustahil_meaning

  @spec correct_answer?(map(), :meaning | :opposite | :opposite_meaning, String.t()) :: boolean()
  def correct_answer?(pair, kind, answer), do: correct_answer(pair, kind) == answer

  @spec key_id(map(), :meaning | :opposite | :opposite_meaning) :: String.t()
  def key_id(pair, kind), do: "#{pair.id}:#{kind}"

  @spec next_question_kind(:meaning | :opposite | :opposite_meaning) ::
          :meaning | :opposite | :opposite_meaning
  def next_question_kind(:meaning), do: :opposite
  def next_question_kind(:opposite), do: :opposite_meaning
  def next_question_kind(:opposite_meaning), do: :meaning

  @spec previous_question_kind(:meaning | :opposite | :opposite_meaning) ::
          :meaning | :opposite | :opposite_meaning
  def previous_question_kind(:meaning), do: :opposite_meaning
  def previous_question_kind(:opposite), do: :meaning
  def previous_question_kind(:opposite_meaning), do: :opposite

  @spec pairs_for([String.t()]) :: [map()]
  def pairs_for(ids) do
    ids = MapSet.new(ids)
    Enum.filter(@curriculum, &MapSet.member?(ids, &1.id))
  end

  defp valid_ids?(ids) do
    ids == Enum.uniq(ids) and Enum.all?(ids, &is_binary/1) and ordered_ids(ids) == ids
  end

  defp valid_key_ids?(ids) do
    ids == Enum.uniq(ids) and Enum.all?(ids, &is_binary/1) and
      length(ordered_key_ids(ids)) == length(ids)
  end

  defp progress_from_keys(mastered_key_ids, review_key_ids, correct_answers, incorrect_answers) do
    mastered_key_ids = ordered_key_ids(mastered_key_ids)
    review_key_ids = review_key_ids |> ordered_key_ids() |> Enum.reject(&(&1 in mastered_key_ids))

    %{
      "version" => @progress_version,
      "learned_ids" => complete_pair_ids(mastered_key_ids),
      "review_ids" => review_pair_ids(review_key_ids),
      "mastered_key_ids" => mastered_key_ids,
      "review_key_ids" => review_key_ids,
      "correct_answers" => correct_answers,
      "incorrect_answers" => incorrect_answers
    }
  end

  defp update_key_progress(progress, add_mastered, add_review, correct_delta, incorrect_delta) do
    mastered_key_ids =
      progress["mastered_key_ids"]
      |> Kernel.++(add_mastered)
      |> Enum.uniq()
      |> Kernel.--(add_review)

    review_key_ids =
      progress["review_key_ids"]
      |> Kernel.++(add_review)
      |> Enum.uniq()
      |> Kernel.--(add_mastered)

    progress_from_keys(
      mastered_key_ids,
      review_key_ids,
      progress["correct_answers"] + correct_delta,
      progress["incorrect_answers"] + incorrect_delta
    )
  end

  defp complete_pair_ids(mastered_key_ids) do
    mastered = MapSet.new(mastered_key_ids)

    @curriculum
    |> Enum.filter(fn pair -> Enum.all?(pair_key_ids(pair.id), &MapSet.member?(mastered, &1)) end)
    |> Enum.map(& &1.id)
  end

  defp review_pair_ids(review_key_ids) do
    review = MapSet.new(review_key_ids)

    @curriculum
    |> Enum.filter(fn pair -> Enum.any?(pair_key_ids(pair.id), &MapSet.member?(review, &1)) end)
    |> Enum.map(& &1.id)
  end

  defp pair_key_ids(id), do: Enum.map(@question_kinds, &"#{id}:#{&1}")

  defp ordered_key_ids(ids) do
    selected = MapSet.new(ids)

    @curriculum
    |> Enum.flat_map(&pair_key_ids(&1.id))
    |> Enum.filter(&MapSet.member?(selected, &1))
  end

  defp arrange_answer_options(pair, kind, options) do
    correct = correct_answer(pair, kind)
    distractors = options |> Enum.uniq() |> List.delete(correct)
    position = stable_answer_position(pair, kind, length(distractors) + 1)

    List.insert_at(distractors, position, correct)
  end

  defp stable_answer_position(pair, kind, answer_count) do
    pair_index = Enum.find_index(@curriculum, &(&1.id == pair.id)) || 0

    kind_offset =
      case kind do
        :meaning -> 1
        :opposite -> 2
        :opposite_meaning -> 3
      end

    rem(pair_index * pair_index + pair_index * 3 + kind_offset, answer_count)
  end

  defp cycle_quiz_pairs(progress, pair, direction) do
    pairs =
      case unlearned_pairs(progress) do
        [] -> @curriculum
        unlearned -> unlearned
      end

    index =
      case Enum.find_index(pairs, &(&1.id == pair.id)) do
        nil when direction == :next -> -1
        nil -> 0
        pair_index -> pair_index
      end

    case direction do
      :next -> Enum.at(pairs, rem(index + 1, length(pairs)))
      :previous -> Enum.at(pairs, rem(index - 1 + length(pairs), length(pairs)))
    end
  end

  defp ordered_ids(ids) do
    selected = MapSet.new(ids)

    @curriculum
    |> Enum.map(& &1.id)
    |> Enum.filter(&MapSet.member?(selected, &1))
  end
end
