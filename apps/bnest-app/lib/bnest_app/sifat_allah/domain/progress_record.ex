defmodule BnestApp.SifatAllah.Domain.ProgressRecord do
  @moduledoc """
  The `sifat-allah-progress` record that stores a learner's progress and current session.

  A learning snapshot is the progress (see `BnestApp.SifatAllah.Domain.Quiz`) with the
  learner's session under `"session"`; the record keeps the two apart. The record store
  assigns `revision`; this module never sets it.
  """

  @doc "The stored record's `recordType`."
  @spec record_type() :: String.t()
  def record_type, do: "sifat-allah-progress"

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
      "progress" => Map.delete(snapshot, "session"),
      "session" => snapshot["session"],
      "updatedAt" => now |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  @doc "The revision a write over `previous` expects: its own, or `nil` for a new record."
  @spec expected_revision(map() | nil) :: non_neg_integer() | nil
  def expected_revision(nil), do: nil
  def expected_revision(previous), do: previous["revision"]
end
