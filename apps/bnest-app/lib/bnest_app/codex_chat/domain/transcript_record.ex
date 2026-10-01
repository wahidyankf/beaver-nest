defmodule BnestApp.CodexChat.Domain.TranscriptRecord do
  @moduledoc """
  The `chat` record that stores a user's transcript snapshot (see
  `BnestApp.CodexChat.Domain.Transcript.snapshot/1`) under `"state"`. The record store
  assigns `revision`; this module never sets it.
  """

  @doc "The stored record's `recordType`."
  @spec record_type() :: String.t()
  def record_type, do: "chat"

  @doc """
  The record that stores `snapshot` for `owner_id` at `now`. It keeps the import source of
  `previous`, the record it replaces (`nil` when there is none).
  """
  @spec record(String.t(), map(), map() | nil, DateTime.t()) :: map()
  def record(owner_id, snapshot, previous, now) do
    %{
      "schemaVersion" => 1,
      "recordType" => record_type(),
      "ownerId" => owner_id,
      "sourceImportId" => if(previous, do: previous["sourceImportId"], else: nil),
      "state" => snapshot,
      "updatedAt" => now |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  @doc "The revision a write over `previous` expects: its own, or `nil` for a new record."
  @spec expected_revision(map() | nil) :: non_neg_integer() | nil
  def expected_revision(nil), do: nil
  def expected_revision(previous), do: previous["revision"]
end
