defmodule BnestApp.Chat do
  @moduledoc false

  @type message :: %{
          id: pos_integer(),
          role: :visitor | :assistant,
          content: String.t(),
          streaming: boolean(),
          update_count: non_neg_integer()
        }

  @type t :: %{
          messages: [message()],
          next_id: pos_integer(),
          busy: boolean(),
          error: String.t() | nil
        }

  @spec new() :: t()
  def new do
    %{messages: [], next_id: 1, busy: false, error: nil}
  end

  @spec submit(t(), String.t()) :: {:ok, t()} | {:error, t()}
  def submit(%{busy: true} = chat, _prompt), do: {:error, chat}

  def submit(chat, prompt) do
    case String.trim(prompt) do
      "" ->
        {:error, chat}

      content ->
        visitor = message(chat.next_id, :visitor, content, false)
        assistant = message(chat.next_id + 1, :assistant, "", true)

        {:ok,
         %{
           chat
           | messages: chat.messages ++ [visitor, assistant],
             next_id: chat.next_id + 2,
             busy: true,
             error: nil
         }}
    end
  end

  @spec update_assistant(t(), String.t()) :: t()
  def update_assistant(chat, text) do
    update_last_assistant(chat, fn message ->
      if message.content == text do
        message
      else
        %{message | content: text, update_count: message.update_count + 1}
      end
    end)
  end

  @spec complete(t()) :: t()
  def complete(chat) do
    chat
    |> update_last_assistant(&%{&1 | streaming: false})
    |> Map.put(:busy, false)
  end

  @spec fail(t(), String.t()) :: t()
  def fail(chat, message) do
    chat
    |> update_last_assistant(&%{&1 | streaming: false})
    |> Map.merge(%{busy: false, error: message})
  end

  defp message(id, role, content, streaming) do
    %{id: id, role: role, content: content, streaming: streaming, update_count: 0}
  end

  defp update_last_assistant(chat, update) do
    %{chat | messages: List.update_at(chat.messages, -1, update)}
  end
end
