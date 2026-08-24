defmodule BnestApp.SifatAllah do
  @moduledoc false

  @progress_version 1

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
      "correct_answers" => 0,
      "incorrect_answers" => 0
    }
  end

  @spec restore(map()) :: {:ok, map()} | :error
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
       %{
         "version" => @progress_version,
         "learned_ids" => ordered_ids(learned_ids),
         "review_ids" => ordered_ids(review_ids),
         "correct_answers" => correct_answers,
         "incorrect_answers" => incorrect_answers
       }}
    else
      false -> :error
    end
  end

  def restore(_snapshot), do: :error

  @spec remember(map(), String.t()) :: map()
  def remember(progress, id) do
    Map.update!(progress, "learned_ids", &ordered_ids([id | &1]))
  end

  @spec record_answer(map(), map(), boolean()) :: map()
  def record_answer(progress, pair, true) do
    progress
    |> Map.update!("correct_answers", &(&1 + 1))
    |> Map.update!("review_ids", &List.delete(&1, pair.id))
  end

  def record_answer(progress, pair, false) do
    progress
    |> Map.update!("incorrect_answers", &(&1 + 1))
    |> Map.update!("review_ids", &ordered_ids([pair.id | &1]))
  end

  @spec learned_count(map()) :: non_neg_integer()
  def learned_count(progress), do: length(progress["learned_ids"])

  @spec correct_count(map()) :: non_neg_integer()
  def correct_count(progress), do: progress["correct_answers"]

  @spec lesson_pairs(map()) :: [map()]
  def lesson_pairs(progress) do
    learned_ids = MapSet.new(progress["learned_ids"])

    @curriculum
    |> Enum.reject(&MapSet.member?(learned_ids, &1.id))
    |> Enum.take(3)
    |> case do
      [] -> Enum.take(@curriculum, 3)
      pairs -> pairs
    end
  end

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
    progress
    |> lesson_pairs()
    |> List.first()
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

  @spec answer_options(map(), :meaning | :opposite) :: [String.t()]
  def answer_options(pair, :meaning) do
    [pair.wajib_meaning, "Dahulu", "Kekal", "Lemah"]
    |> Enum.uniq()
  end

  def answer_options(pair, :opposite) do
    [pair.mustahil, "Hudus", "Fana’", "‘Ajzun"]
    |> Enum.uniq()
  end

  @spec correct_answer?(map(), :meaning | :opposite, String.t()) :: boolean()
  def correct_answer?(pair, :meaning, answer), do: answer == pair.wajib_meaning
  def correct_answer?(pair, :opposite, answer), do: answer == pair.mustahil

  @spec pairs_for([String.t()]) :: [map()]
  def pairs_for(ids) do
    ids = MapSet.new(ids)
    Enum.filter(@curriculum, &MapSet.member?(ids, &1.id))
  end

  defp valid_ids?(ids) do
    ids == Enum.uniq(ids) and Enum.all?(ids, &is_binary/1) and ordered_ids(ids) == ids
  end

  defp ordered_ids(ids) do
    selected = MapSet.new(ids)

    @curriculum
    |> Enum.map(& &1.id)
    |> Enum.filter(&MapSet.member?(selected, &1))
  end
end
