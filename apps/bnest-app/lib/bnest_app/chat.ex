defmodule BnestApp.Chat do
  @moduledoc false

  @snapshot_version 1
  @max_messages 200
  @max_content_bytes 100_000
  @max_thread_id_bytes 512

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
          error: String.t() | nil,
          thread_id: String.t() | nil
        }

  @spec new() :: t()
  def new do
    %{messages: [], next_id: 1, busy: false, error: nil, thread_id: nil}
  end

  @spec put_thread_id(t(), String.t()) :: t()
  def put_thread_id(chat, thread_id) when is_binary(thread_id) do
    if valid_thread_id?(thread_id), do: %{chat | thread_id: thread_id}, else: chat
  end

  @spec snapshot(t()) :: {:ok, map()} | :error
  def snapshot(%{busy: false, messages: messages, thread_id: thread_id}) do
    if messages == [] or valid_thread_id?(thread_id) do
      {:ok,
       %{
         "version" => @snapshot_version,
         "thread_id" => thread_id,
         "messages" => Enum.map(messages, &snapshot_message/1)
       }}
    else
      :error
    end
  end

  def snapshot(_chat), do: :error

  @spec restore(term()) :: {:ok, t()} | :error
  def restore(%{
        "version" => @snapshot_version,
        "thread_id" => thread_id,
        "messages" => messages
      })
      when is_list(messages) and length(messages) <= @max_messages do
    with true <- valid_snapshot_thread?(thread_id, messages),
         {:ok, restored_messages} <- restore_messages(messages) do
      {:ok,
       %{
         messages: restored_messages,
         next_id: next_id(restored_messages),
         busy: false,
         error: nil,
         thread_id: thread_id
       }}
    else
      _invalid -> :error
    end
  end

  def restore(_snapshot), do: :error

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

  defp snapshot_message(message) do
    %{
      "id" => message.id,
      "role" => Atom.to_string(message.role),
      "content" => message.content,
      "update_count" => message.update_count
    }
  end

  defp restore_messages(messages) do
    messages
    |> Enum.reduce_while({:ok, [], 1}, fn snapshot, {:ok, restored, expected_id} ->
      case restore_message(snapshot, expected_id) do
        {:ok, message} -> {:cont, {:ok, [message | restored], expected_id + 1}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, restored, _next_id} -> validate_roles(Enum.reverse(restored))
      :error -> :error
    end
  end

  defp restore_message(
         %{
           "id" => id,
           "role" => role,
           "content" => content,
           "update_count" => update_count
         },
         id
       )
       when role in ["visitor", "assistant"] and is_binary(content) and
              byte_size(content) <= @max_content_bytes and is_integer(update_count) and
              update_count >= 0 do
    {:ok,
     %{
       id: id,
       role: if(role == "visitor", do: :visitor, else: :assistant),
       content: content,
       streaming: false,
       update_count: update_count
     }}
  end

  defp restore_message(_snapshot, _expected_id), do: :error

  defp validate_roles(messages) do
    roles = Enum.map(messages, & &1.role)

    if roles == Enum.take(Stream.cycle([:visitor, :assistant]), length(roles)) do
      {:ok, messages}
    else
      :error
    end
  end

  defp next_id([]), do: 1
  defp next_id(messages), do: List.last(messages).id + 1

  defp valid_snapshot_thread?(nil, []), do: true
  defp valid_snapshot_thread?(thread_id, _messages), do: valid_thread_id?(thread_id)

  defp valid_thread_id?(thread_id) when is_binary(thread_id) do
    byte_size(thread_id) in 1..@max_thread_id_bytes
  end

  defp valid_thread_id?(_thread_id), do: false

  defp update_last_assistant(chat, update) do
    %{chat | messages: List.update_at(chat.messages, -1, update)}
  end
end
