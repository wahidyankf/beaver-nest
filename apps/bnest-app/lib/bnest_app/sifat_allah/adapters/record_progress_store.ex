defmodule BnestApp.SifatAllah.Adapters.RecordProgressStore do
  @moduledoc """
  The `BnestApp.SifatAllah.Ports.ProgressStore` over Storage's routed record repository,
  `BnestApp.Storage.Records`. It keeps the `:sifat_allah` record kind keyed by the owner's
  `userId`, so stored learning progress is unchanged.
  """

  @behaviour BnestApp.SifatAllah.Ports.ProgressStore

  alias BnestApp.Storage.Records

  @type t :: %{adapter: module(), records: GenServer.server()}

  @impl true
  @spec new() :: t()
  def new, do: %{adapter: __MODULE__, records: Records}

  @impl true
  def read(%{records: records}, owner_id), do: Records.read(:sifat_allah, owner_id, records)

  @impl true
  def write(%{records: records}, owner_id, expected_revision, record),
    do: Records.write(:sifat_allah, owner_id, expected_revision, record, records)
end
