defmodule BnestApp.CodexChat.Adapters.TranscriptRecordKind do
  @moduledoc """
  Registers the chat transcript as a Storage record kind: the record holds the serialized chat
  state, imported from the browser's session storage.
  """

  @behaviour BnestApp.Storage.Ports.RecordKind

  alias BnestApp.CodexChat.Domain.{Conversations, TranscriptRecord}
  alias BnestApp.Storage.Domain.RecordSchema

  @impl true
  def kind, do: :chat

  @impl true
  def record_type, do: TranscriptRecord.record_type()

  @impl true
  def source, do: {"sessionStorage", "bnest.chat.v1"}

  @impl true
  def valid?(record) do
    RecordSchema.exact?(record, ["state" | RecordSchema.envelope_fields()]) and
      match?(
        {:ok, _conversations},
        Conversations.restore(record["state"], DateTime.utc_now())
      )
  end

  @impl true
  def normalize(source) do
    # A source written before conversations existed is a single transcript, which
    # restores into one conversation; anything newer round-trips as it is.
    with {:ok, conversations} <- Conversations.restore(source, DateTime.utc_now()),
         {:ok, state} <- Conversations.snapshot(conversations) do
      {:ok, %{"state" => state}}
    else
      _invalid -> :error
    end
  end
end
