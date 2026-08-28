defmodule BnestApp.Chat do
  @moduledoc false

  alias BnestApp.Codex.Settings

  @snapshot_version 4
  @max_messages 200
  @max_content_bytes 100_000
  @max_thread_id_bytes 512
  @max_model_bytes 128
  @max_runner_item_id_bytes 512
  @max_progress_items 20
  @max_progress_content_bytes 20_000
  @reasoning_efforts ~w(none minimal low medium high xhigh max ultra)

  @type progress_kind :: :reasoning | :activity | :status

  @type progress_item :: %{
          item_id: String.t(),
          kind: progress_kind(),
          content: String.t()
        }

  @type message :: %{
          id: pos_integer(),
          role: :visitor | :assistant,
          content: String.t(),
          streaming: boolean(),
          update_count: non_neg_integer(),
          active_item_id: String.t() | nil,
          progress: [progress_item()]
        }

  @type t :: %{
          messages: [message()],
          next_id: pos_integer(),
          busy: boolean(),
          pending_turn: map() | nil,
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
      pending_turn: nil,
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

  @spec enforce_model(t(), String.t(), String.t()) :: t()
  def enforce_model(chat, model, reasoning_effort)
      when is_binary(model) and byte_size(model) > 0 and is_binary(reasoning_effort) and
             reasoning_effort in @reasoning_efforts do
    %{chat | model: model, reasoning_effort: reasoning_effort}
  end

  @spec put_thread_id(t(), String.t()) :: t()
  def put_thread_id(chat, thread_id) when is_binary(thread_id) do
    if valid_thread_id?(thread_id), do: %{chat | thread_id: thread_id}, else: chat
  end

  @spec snapshot(t()) :: {:ok, map()} | :error
  def snapshot(%{
        busy: busy,
        pending_turn: pending_turn,
        messages: messages,
        thread_id: thread_id,
        model: model,
        reasoning_effort: reasoning_effort
      }) do
    if is_boolean(busy) and valid_pending_turn?(pending_turn, messages, busy) and
         valid_snapshot_thread?(thread_id, messages) and valid_model?(model) and
         reasoning_effort in @reasoning_efforts do
      {:ok,
       %{
         "version" => @snapshot_version,
         "thread_id" => thread_id,
         "model" => model,
         "reasoning_effort" => reasoning_effort,
         "messages" => Enum.map(messages, &snapshot_message/1),
         "pending_turn" => snapshot_pending_turn(pending_turn)
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
        "messages" => messages,
        "pending_turn" => pending_turn
      })
      when is_list(messages) and length(messages) <= @max_messages do
    with true <- valid_snapshot_thread?(thread_id, messages),
         true <- valid_model?(model),
         true <- reasoning_effort in @reasoning_efforts,
         {:ok, restored_messages} <- restore_messages(messages),
         {:ok, restored_pending_turn} <- restore_pending_turn(pending_turn, restored_messages) do
      {:ok,
       %{
         messages: restored_messages,
         next_id: next_id(restored_messages),
         busy: not is_nil(restored_pending_turn),
         pending_turn: restored_pending_turn,
         error: nil,
         thread_id: thread_id,
         model: model,
         reasoning_effort: reasoning_effort
       }}
    else
      _invalid -> :error
    end
  end

  def restore(%{"version" => version, "messages" => messages} = snapshot)
      when version in [1, 2, 3] do
    restore(
      snapshot
      |> Map.put("version", @snapshot_version)
      |> Map.put_new("model", Settings.preferred_model())
      |> Map.put_new("reasoning_effort", Settings.preferred_reasoning_effort())
      |> Map.put_new("pending_turn", nil)
      |> Map.put("messages", Enum.map(messages, &upgrade_message/1))
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
             pending_turn: %{
               prompt: content,
               assistant_message_id: assistant.id,
               continuation_attempted: false
             },
             error: nil
         }}
    end
  end

  @spec update_assistant(t(), String.t()) :: t()
  def update_assistant(chat, text) when is_binary(text),
    do: update_assistant(chat, "assistant-message", text)

  @spec update_assistant(t(), String.t(), String.t()) :: t()
  def update_assistant(chat, item_id, text)
      when is_binary(item_id) and is_binary(text) do
    if valid_runner_item_id?(item_id) do
      update_last_assistant(chat, fn message ->
        update_assistant_message(message, item_id, text)
      end)
    else
      chat
    end
  end

  def update_assistant(chat, _item_id, _text), do: chat

  @spec update_progress(t(), String.t(), progress_kind(), String.t()) :: t()
  def update_progress(chat, item_id, kind, text)
      when is_binary(item_id) and kind in [:reasoning, :activity, :status] and is_binary(text) do
    if valid_runner_item_id?(item_id) do
      case normalize_progress_content(text) do
        "" -> chat
        content -> update_last_assistant(chat, &upsert_progress(&1, item_id, kind, content))
      end
    else
      chat
    end
  end

  def update_progress(chat, _item_id, _kind, _text), do: chat

  @spec complete(t()) :: t()
  def complete(chat) do
    chat
    |> update_last_assistant(&%{&1 | streaming: false})
    |> Map.merge(%{busy: false, pending_turn: nil})
  end

  @spec fail(t(), String.t()) :: t()
  def fail(chat, message) do
    chat
    |> update_last_assistant(&%{&1 | streaming: false})
    |> Map.merge(%{busy: false, pending_turn: nil, error: message})
  end

  @spec continuation_prompt(t()) :: {:ok, String.t(), t()} | {:error, :none | :already_attempted}
  def continuation_prompt(%{pending_turn: nil}), do: {:error, :none}

  def continuation_prompt(%{pending_turn: %{continuation_attempted: true}}),
    do: {:error, :already_attempted}

  def continuation_prompt(%{pending_turn: pending_turn, thread_id: thread_id} = chat) do
    prompt =
      if is_nil(thread_id) do
        pending_turn.prompt
      else
        "Continue the previous answer to the user's latest request. Do not repeat text already shown."
      end

    {:ok, prompt, put_in(chat, [:pending_turn, :continuation_attempted], true)}
  end

  defp message(id, role, content, streaming) do
    %{
      id: id,
      role: role,
      content: content,
      streaming: streaming,
      update_count: 0,
      active_item_id: nil,
      progress: []
    }
  end

  defp snapshot_message(message) do
    %{
      "id" => message.id,
      "role" => Atom.to_string(message.role),
      "content" => message.content,
      "update_count" => message.update_count,
      "active_item_id" => message.active_item_id,
      "progress" => Enum.map(message.progress, &snapshot_progress_item/1)
    }
  end

  defp snapshot_progress_item(%{item_id: item_id, kind: kind, content: content}) do
    %{"item_id" => item_id, "kind" => Atom.to_string(kind), "content" => content}
  end

  defp upgrade_message(message) when is_map(message) do
    message
    |> Map.put_new("active_item_id", nil)
    |> Map.put_new("progress", [])
  end

  defp upgrade_message(message), do: message

  defp snapshot_pending_turn(nil), do: nil

  defp snapshot_pending_turn(%{
         prompt: prompt,
         assistant_message_id: assistant_message_id,
         continuation_attempted: continuation_attempted
       }) do
    %{
      "prompt" => prompt,
      "assistant_message_id" => assistant_message_id,
      "continuation_attempted" => continuation_attempted
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
           "update_count" => update_count,
           "active_item_id" => active_item_id,
           "progress" => progress
         },
         id
       )
       when role in ["visitor", "assistant"] and is_binary(content) and
              byte_size(content) <= @max_content_bytes and is_integer(update_count) and
              update_count >= 0 do
    with true <- valid_active_item_id?(active_item_id),
         {:ok, restored_progress} <- restore_progress(progress) do
      {:ok,
       %{
         id: id,
         role: if(role == "visitor", do: :visitor, else: :assistant),
         content: content,
         streaming: false,
         update_count: update_count,
         active_item_id: active_item_id,
         progress: restored_progress
       }}
    else
      _invalid -> :error
    end
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

  defp valid_runner_item_id?(item_id) when is_binary(item_id),
    do: byte_size(item_id) in 1..@max_runner_item_id_bytes

  defp valid_runner_item_id?(_item_id), do: false

  defp valid_active_item_id?(nil), do: true
  defp valid_active_item_id?(item_id), do: valid_runner_item_id?(item_id)

  defp restore_progress(progress)
       when is_list(progress) and length(progress) <= @max_progress_items do
    progress
    |> Enum.reduce_while({:ok, []}, fn progress_item, {:ok, restored} ->
      case restore_progress_item(progress_item) do
        {:ok, item} -> {:cont, {:ok, [item | restored]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, restored} ->
        restored = Enum.reverse(restored)

        if Enum.uniq_by(restored, & &1.item_id) == restored, do: {:ok, restored}, else: :error

      :error ->
        :error
    end
  end

  defp restore_progress(_progress), do: :error

  defp restore_progress_item(%{"item_id" => item_id, "kind" => kind, "content" => content})
       when kind in ["reasoning", "activity", "status"] and is_binary(content) and
              byte_size(content) in 1..@max_progress_content_bytes do
    if valid_runner_item_id?(item_id) do
      {:ok, %{item_id: item_id, kind: String.to_existing_atom(kind), content: content}}
    else
      :error
    end
  end

  defp restore_progress_item(_progress_item), do: :error

  defp valid_pending_turn?(nil, _messages, false), do: true

  defp valid_pending_turn?(%{} = pending_turn, messages, true) do
    match?(
      {:ok, _pending_turn},
      restore_pending_turn(snapshot_pending_turn(pending_turn), messages)
    )
  end

  defp valid_pending_turn?(_pending_turn, _messages, _busy), do: false

  defp restore_pending_turn(nil, _messages), do: {:ok, nil}

  defp restore_pending_turn(
         %{
           "prompt" => prompt,
           "assistant_message_id" => assistant_message_id,
           "continuation_attempted" => continuation_attempted
         },
         messages
       )
       when is_binary(prompt) and byte_size(prompt) in 1..@max_content_bytes and
              is_integer(assistant_message_id) and is_boolean(continuation_attempted) do
    case List.last(messages) do
      %{id: ^assistant_message_id, role: :assistant} ->
        {:ok,
         %{
           prompt: prompt,
           assistant_message_id: assistant_message_id,
           continuation_attempted: continuation_attempted
         }}

      _other ->
        :error
    end
  end

  defp restore_pending_turn(_pending_turn, _messages), do: :error

  defp update_last_assistant(chat, update) do
    %{chat | messages: List.update_at(chat.messages, -1, update)}
  end

  defp update_assistant_message(message, item_id, text) do
    cond do
      message.active_item_id == item_id and message.content == text ->
        message

      message.active_item_id == item_id ->
        %{message | content: text, update_count: message.update_count + 1}

      message.content == "" ->
        %{
          message
          | active_item_id: item_id,
            content: text,
            update_count: message.update_count + 1
        }

      true ->
        message
        |> upsert_progress(
          message.active_item_id || "assistant-message",
          :status,
          message.content
        )
        |> Map.merge(%{
          active_item_id: item_id,
          content: text,
          update_count: message.update_count + 1
        })
    end
  end

  defp upsert_progress(message, item_id, kind, content) do
    progress_item = %{item_id: item_id, kind: kind, content: content}

    progress =
      case Enum.find_index(message.progress, &(&1.item_id == item_id)) do
        nil -> Enum.take(message.progress ++ [progress_item], -@max_progress_items)
        index -> List.replace_at(message.progress, index, progress_item)
      end

    %{message | progress: progress}
  end

  defp normalize_progress_content(text) do
    text
    |> String.trim()
    |> String.slice(0, @max_progress_content_bytes)
  end
end
