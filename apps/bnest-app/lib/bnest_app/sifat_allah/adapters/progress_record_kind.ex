defmodule BnestApp.SifatAllah.Adapters.ProgressRecordKind do
  @moduledoc """
  Registers the Sifat Allah learning progress as a Storage record kind: the record holds the
  progress and the learner's current session, imported from the browser's local storage.
  """

  @behaviour BnestApp.Storage.Ports.RecordKind

  alias BnestApp.SifatAllah
  alias BnestApp.Storage.Domain.RecordSchema

  @dashboard %{"mode" => "dashboard"}

  @impl true
  def kind, do: :sifat_allah

  @impl true
  def record_type, do: "sifat-allah-progress"

  @impl true
  def source, do: {"localStorage", "bnest.sifat-allah.v1"}

  @impl true
  def valid?(record) do
    RecordSchema.exact?(record, ["progress", "session" | RecordSchema.envelope_fields()]) and
      valid_progress?(record["progress"]) and valid_learning_session?(record["session"])
  end

  # An unknown or damaged saved session falls back to the dashboard instead of failing the
  # whole import, so the learner keeps their progress.
  @impl true
  def normalize(source) do
    case SifatAllah.restore(source) do
      {:ok, progress} ->
        session = source["session"] || @dashboard

        session =
          if valid_progress?(progress) and valid_learning_session?(session),
            do: session,
            else: @dashboard

        {:ok, %{"progress" => progress, "session" => session}}

      _invalid ->
        :error
    end
  end

  defp valid_progress?(progress) do
    RecordSchema.exact?(
      progress,
      ~w(version learned_ids review_ids mastered_key_ids review_key_ids correct_answers incorrect_answers)
    ) and
      match?({:ok, _progress}, SifatAllah.restore(progress))
  end

  defp valid_learning_session?(nil), do: true

  defp valid_learning_session?(%{"mode" => "dashboard"} = session),
    do: RecordSchema.exact?(session, ~w(mode))

  defp valid_learning_session?(%{"mode" => "study"} = session),
    do:
      RecordSchema.exact?(session, ~w(mode lesson_ids lesson_index feedback)) and
        RecordSchema.nonempty_list?(session["lesson_ids"], &RecordSchema.id?/1) and
        RecordSchema.revision?(session["lesson_index"]) and
        session["feedback"] in [nil, "remembered"]

  defp valid_learning_session?(%{"mode" => "quiz"} = session),
    do:
      RecordSchema.exact?(session, ~w(mode quiz_pair_id quiz_kind quiz_scope feedback)) and
        RecordSchema.id?(session["quiz_pair_id"]) and is_binary(session["quiz_kind"]) and
        session["quiz_scope"] in ~w(all learned) and
        session["feedback"] in [nil, "success", "retry"]

  defp valid_learning_session?(%{"mode" => "review"} = session),
    do:
      RecordSchema.exact?(session, ~w(mode review_pair_id review_kind feedback)) and
        RecordSchema.id?(session["review_pair_id"]) and is_binary(session["review_kind"]) and
        session["feedback"] in [nil, "success", "retry"]

  defp valid_learning_session?(_session), do: false
end
