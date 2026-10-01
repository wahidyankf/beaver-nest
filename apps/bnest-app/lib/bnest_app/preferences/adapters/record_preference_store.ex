defmodule BnestApp.Preferences.Adapters.RecordPreferenceStore do
  @moduledoc """
  The `BnestApp.Preferences.Ports.PreferenceStore` over Storage's routed record repository,
  `BnestApp.Storage.Records`. It keeps the `:theme` record kind keyed by the owner's
  `userId`, so stored preferences are unchanged.
  """

  @behaviour BnestApp.Preferences.Ports.PreferenceStore

  alias BnestApp.Storage.Records

  @type t :: %{adapter: module(), records: GenServer.server()}

  @impl true
  @spec new() :: t()
  def new, do: %{adapter: __MODULE__, records: Records}

  @impl true
  def read(%{records: records}, owner_id), do: Records.read(:theme, owner_id, records)

  @impl true
  def write(%{records: records}, owner_id, expected_revision, record),
    do: Records.write(:theme, owner_id, expected_revision, record, records)

  @impl true
  def remove_exact(%{records: records}, owner_id, expected),
    do: Records.remove_exact(:theme, owner_id, expected, records)
end
