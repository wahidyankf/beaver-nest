defmodule BnestApp.CodexChat.Adapters.TranscriptRecordKind do
  @moduledoc """
  Registers the chat transcript as a Storage record kind: the record holds the serialized chat
  state, imported from the browser's session storage.
  """

  @behaviour BnestApp.Storage.Ports.RecordKind

  alias BnestApp.Chat
  alias BnestApp.Storage.Domain.RecordSchema

  @impl true
  def kind, do: :chat

  @impl true
  def record_type, do: "chat"

  @impl true
  def source, do: {"sessionStorage", "bnest.chat.v1"}

  @impl true
  def valid?(record) do
    RecordSchema.exact?(record, ["state" | RecordSchema.envelope_fields()]) and
      match?({:ok, _chat}, Chat.restore(record["state"]))
  end

  @impl true
  def normalize(source) do
    with {:ok, chat} <- Chat.restore(source),
         {:ok, state} <- Chat.snapshot(chat) do
      {:ok, %{"state" => state}}
    else
      _invalid -> :error
    end
  end
end
