defmodule BnestApp.Chat do
  @moduledoc false

  alias BnestApp.Codex.Settings

  @snapshot_version 2
  @max_messages 200
  @max_content_bytes 100_000
  @max_thread_id_bytes 512
  @max_model_bytes 128
  @reasoning_efforts ~w(none minimal low medium high xhigh max ultra)

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
          thread_id: String.t() | nil,
          model: String.t(),
          reasoning_effort: String.t()
        }

  @spec new(String.t(), String.t()) :: t()
  def new(
        model \\ Settings.preferred_model(),
        reasoning_effort \\ Settings.preferred_reasoning_effort()
      ) do
    %{
      messages: [],
      next_id: 1,
      busy: false,
      error: nil,
      thread_id: nil,
      model: model,
      reasoning_effort: reasoning_effort
    }
  end

  @spec select_model(t(), String.t(), String.t()) :: {:ok, t()} | {:error, t()}
  def select_model(%{busy: true} = chat, _model, _reasoning_effort), do: {:error, chat}

  def select_model(chat, model, reasoning_effort) do
    if valid_model?(model) and reasoning_effort in @reasoning_efforts do
      {:ok, %{chat | model: model, reasoning_effort: reasoning_effort, error: nil}}
    else
      {:error, chat}
    end
  end

  @spec put_thread_id(t(), String.t()) :: t()
  def put_thread_id(chat, thread_id) when is_binary(thread_id) do
    if valid_thread_id?(thread_id), do: %{chat | thread_id: thread_id}, else: chat
  end

  @spec snapshot(t()) :: {:ok, map()} | :error
  def snapshot(%{
        busy: false,
        messages: messages,
        thread_id: thread_id,
        model: model,
        reasoning_effort: reasoning_effort
      }) do
    if valid_snapshot_thread?(thread_id, messages) and valid_model?(model) and
         reasoning_effort in @reasoning_efforts do
      {:ok,
       %{
         "version" => @snapshot_version,
         "thread_id" => thread_id,
         "model" => model,
         "reasoning_effort" => reasoning_effort,
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
        "model" => model,
        "reasoning_effort" => reasoning_effort,
        "messages" => messages
      })
      when is_list(messages) and length(messages) <= @max_messages do
    with true <- valid_snapshot_thread?(thread_id, messages),
         true <- valid_model?(model),
         true <- reasoning_effort in @reasoning_efforts,
         {:ok, restored_messages} <- restore_messages(messages) do
      {:ok,
       %{
         messages: restored_messages,
         next_id: next_id(restored_messages),
         busy: false,
         error: nil,
         thread_id: thread_id,
         model: model,
         reasoning_effort: reasoning_effort
       }}
    else
      _invalid -> :error
    end
  end

  def restore(%{"version" => 1, "thread_id" => thread_id, "messages" => messages} = snapshot) do
    restore(
      snapshot
      |> Map.put("version", @snapshot_version)
      |> Map.put("model", Settings.preferred_model())
      |> Map.put("reasoning_effort", Settings.preferred_reasoning_effort())
      |> Map.put("thread_id", thread_id)
      |> Map.put("messages", messages)
    )
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

  defp valid_snapshot_thread?(nil, _messages), do: true
  defp valid_snapshot_thread?(thread_id, _messages), do: valid_thread_id?(thread_id)

  defp valid_thread_id?(thread_id) when is_binary(thread_id) do
    byte_size(thread_id) in 1..@max_thread_id_bytes
  end

  defp valid_thread_id?(_thread_id), do: false

  defp valid_model?(model) when is_binary(model), do: byte_size(model) in 1..@max_model_bytes
  defp valid_model?(_model), do: false

  defp update_last_assistant(chat, update) do
    %{chat | messages: List.update_at(chat.messages, -1, update)}
  end
end
