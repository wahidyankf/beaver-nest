defmodule BnestApp.CodexChat.Adapters.RecordTranscriptStore do
  @moduledoc """
  The `BnestApp.CodexChat.Ports.TranscriptStore` over Storage's routed record repository,
  `BnestApp.Storage.Records`. It keeps the `:chat` record kind keyed by the owner's `userId`,
  so stored transcripts are unchanged.
  """

  @behaviour BnestApp.CodexChat.Ports.TranscriptStore

  alias BnestApp.Storage.Records

  @type t :: %{adapter: module(), records: GenServer.server()}

  @impl true
  @spec new() :: t()
  def new, do: %{adapter: __MODULE__, records: Records}

  @impl true
  def read(%{records: records}, owner_id), do: Records.read(:chat, owner_id, records)

  @impl true
  def write(%{records: records}, owner_id, expected_revision, record),
    do: Records.write(:chat, owner_id, expected_revision, record, records)
end
