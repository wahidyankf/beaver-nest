defmodule BnestApp.Preferences.Domain.Theme do
  @moduledoc """
  The theme a user may choose and the `theme-preference` record that stores it.

  `"system"` follows the device and is the default, so it is never stored: choosing it
  removes the record. The record store assigns `revision`; this module never sets it.
  """

  @values ["system", "light", "dark"]

  @type t :: String.t()

  @doc "Every theme a user may choose, the default first."
  @spec values() :: [t()]
  def values, do: @values

  @doc "The theme that applies when the user stored none."
  @spec default() :: t()
  def default, do: "system"

  @spec valid?(term()) :: boolean()
  def valid?(theme), do: theme in @values

  @doc """
  The record that stores `theme` for `owner_id` at `now`. It keeps the import source of
  `previous`, the record it replaces (`nil` when there is none).
  """
  @spec record(String.t(), t(), map() | nil, DateTime.t()) :: map()
  def record(owner_id, theme, previous, now) do
    %{
      "schemaVersion" => 1,
      "recordType" => "theme-preference",
      "ownerId" => owner_id,
      "sourceImportId" => if(previous, do: previous["sourceImportId"], else: nil),
      "theme" => theme,
      "updatedAt" => now |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  @doc "The revision a write over `previous` expects: its own, or `nil` for a new record."
  @spec expected_revision(map() | nil) :: non_neg_integer() | nil
  def expected_revision(nil), do: nil
  def expected_revision(previous), do: previous["revision"]
end
