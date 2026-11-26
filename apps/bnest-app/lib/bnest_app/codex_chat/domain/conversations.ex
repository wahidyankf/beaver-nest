defmodule BnestApp.CodexChat.Domain.Conversations do
  @moduledoc """
  The user's chat conversations: one `:chat` record holds every conversation, as a
  selected id plus a map of conversation snapshots, each with its title and update
  time. A record written before conversations existed holds a single transcript
  snapshot, which restores into one conversation.
  """

  alias BnestApp.CodexChat.Domain.Transcript

  @state_version 1
  @max_conversations 50
  @max_title_scalars 80
  @max_id_bytes 128
  @placeholder_title "New chat"

  @type entry :: %{
          transcript: Transcript.t(),
          title: String.t(),
          updated_at: DateTime.t()
        }

  @type t :: %{
          selected_id: String.t() | nil,
          conversations: %{String.t() => entry()}
        }

  @type listed :: %{id: String.t(), title: String.t(), updated_at: DateTime.t()}
  @type selected :: %{
          id: String.t(),
          title: String.t(),
          updated_at: DateTime.t(),
          transcript: Transcript.t()
        }

  @doc """
  A fresh set with one selected conversation. `transcript:`, `id:`, `title:` and
  `now:` override the empty defaults, so a test can name them.
  """
  @spec new(keyword()) :: t()
  def new(options \\ []) do
    now = Keyword.fetch!(options, :now)
    id = Keyword.get_lazy(options, :id, &random_id/0)
    title = options |> Keyword.get(:title, @placeholder_title) |> new_title()

    %{selected_id: nil, conversations: %{}}
    |> put_entry(
      id,
      Keyword.get(options, :transcript, Transcript.new()),
      title,
      now
    )
    |> select_newest_fallback()
  end

  @doc """
  Opens a new empty conversation and selects it. Refuses past the limit.
  """
  @spec create(t(), keyword()) :: {:ok, String.t(), t()} | {:error, :too_many}
  def create(%{conversations: conversations} = state, options \\ []) do
    if map_size(conversations) >= @max_conversations do
      {:error, :too_many}
    else
      id = Keyword.get_lazy(options, :id, &random_id/0)
      now = Keyword.fetch!(options, :now)

      {:ok, id,
       %{state | selected_id: id} |> put_entry(id, Transcript.new(), @placeholder_title, now)}
    end
  end

  @doc "Selects the conversation `id`."
  @spec select(t(), String.t()) :: {:ok, t()} | {:error, :unknown_conversation}
  def select(%{conversations: conversations} = state, id) do
    if Map.has_key?(conversations, id),
      do: {:ok, %{state | selected_id: id}},
      else: {:error, :unknown_conversation}
  end

  @doc """
  Deletes the conversation `id`. Deleting the selected conversation falls back to
  the most recently updated one; deleting the last one reseeds a fresh conversation.
  """
  @spec delete(t(), String.t(), keyword()) :: {:ok, t()} | {:error, :unknown_conversation}
  def delete(%{conversations: conversations} = state, id, options \\ []) do
    if Map.has_key?(conversations, id) do
      remaining = Map.delete(conversations, id)

      next =
        cond do
          map_size(remaining) == 0 ->
            fresh_id = Keyword.get_lazy(options, :id, &random_id/0)
            now = Keyword.fetch!(options, :now)

            put_entry(
              %{state | selected_id: fresh_id},
              fresh_id,
              Transcript.new(),
              @placeholder_title,
              now
            )

          state.selected_id == id ->
            %{state | conversations: remaining} |> select_newest_fallback()

          true ->
            %{state | conversations: remaining}
        end

      {:ok, next}
    else
      {:error, :unknown_conversation}
    end
  end

  @doc """
  Renames the conversation `id`. The title is trimmed and capped at eighty
  scalars; a blank title is refused.
  """
  @spec rename(t(), String.t(), String.t(), keyword()) ::
          {:ok, t()} | {:error, :unknown_conversation | :invalid_title}
  def rename(%{conversations: conversations} = state, id, title, options \\ []) do
    with {:ok, _entry} <- fetch(conversations, id),
         {:ok, trimmed} <- clean_title(title) do
      now = Keyword.fetch!(options, :now)
      %{title: _, transcript: transcript} = Map.fetch!(conversations, id)
      {:ok, put_entry(state, id, transcript, trimmed, now)}
    end
  end

  @doc "Stores `transcript` in the conversation `id` and stamps its update time."
  @spec put_transcript(t(), String.t(), Transcript.t(), keyword()) ::
          {:ok, t()} | {:error, :unknown_conversation}
  def put_transcript(%{conversations: conversations} = state, id, transcript, options \\ []) do
    with {:ok, %{title: title}} <- fetch(conversations, id) do
      now = Keyword.fetch!(options, :now)
      {:ok, put_entry(state, id, transcript, title, now)}
    end
  end

  @doc "The selected conversation with its transcript."
  @spec selected(t()) :: {:ok, selected()} | {:error, :missing_conversation}
  def selected(%{selected_id: id, conversations: conversations}) do
    with true <- is_binary(id),
         {:ok, %{transcript: transcript, title: title, updated_at: updated_at}} <-
           fetch(conversations, id) do
      {:ok, %{id: id, title: title, updated_at: updated_at, transcript: transcript}}
    else
      _missing -> {:error, :missing_conversation}
    end
  end

  @doc "Every conversation, newest first."
  @spec list(t()) :: [listed()]
  def list(%{conversations: conversations}) do
    conversations
    |> Enum.map(fn {id, %{title: title, updated_at: updated_at}} ->
      %{id: id, title: title, updated_at: updated_at}
    end)
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
  end

  @doc """
  The title a conversation takes from its first visitor message: trimmed to its
  first line and capped at eighty scalars, or the placeholder when blank.
  """
  @spec title_for(String.t()) :: String.t()
  def title_for(prompt) when is_binary(prompt) do
    prompt
    |> String.trim()
    |> String.split("\n", parts: 2)
    |> hd()
    |> String.trim()
    |> cap_title()
    |> or_placeholder()
  end

  def title_for(_prompt), do: @placeholder_title

  @doc "The placeholder title of a conversation with no user message yet."
  @spec placeholder_title() :: String.t()
  def placeholder_title, do: @placeholder_title

  @doc "Serializes the set for the `:chat` record's state."
  @spec snapshot(t()) :: {:ok, map()} | :error
  def snapshot(%{selected_id: selected_id, conversations: conversations} = _state) do
    with true <- is_binary(selected_id) and Map.has_key?(conversations, selected_id),
         true <- map_size(conversations) in 1..@max_conversations,
         {:ok, snapshots} <- snapshot_entries(conversations) do
      {:ok,
       %{
         "version" => @state_version,
         "selected_id" => selected_id,
         "conversations" => snapshots
       }}
    else
      _invalid -> :error
    end
  end

  def snapshot(_state), do: :error

  @doc """
  Restores a serialized set. A snapshot without a conversations map is a single
  transcript written before conversations existed, which restores into one
  conversation titled from its first visitor message.
  """
  @spec restore(map(), DateTime.t() | nil) :: {:ok, t()} | :error
  def restore(snapshot, now \\ nil)

  def restore(
        %{"version" => @state_version, "selected_id" => selected_id, "conversations" => entries},
        _now
      )
      when is_map(entries) do
    with true <- is_binary(selected_id) and Map.has_key?(entries, selected_id),
         true <- map_size(entries) in 1..@max_conversations,
         {:ok, conversations} <- restore_entries(entries) do
      {:ok, %{selected_id: selected_id, conversations: conversations}}
    else
      _invalid -> :error
    end
  end

  def restore(%{"messages" => _messages} = legacy, %DateTime{} = now) do
    case Transcript.restore(legacy) do
      {:ok, transcript} ->
        id = random_id()

        {:ok,
         %{selected_id: nil, conversations: %{}}
         |> put_entry(id, transcript, legacy_title(transcript), now)
         |> select_newest_fallback()}

      :error ->
        :error
    end
  end

  def restore(%{"messages" => _messages}, _now), do: :error

  def restore(_snapshot, _now), do: :error

  defp put_entry(state, id, transcript, title, now) do
    %{
      state
      | conversations:
          Map.put(state.conversations, id, %{
            transcript: transcript,
            title: title,
            updated_at: now
          })
    }
  end

  # Every caller passes a selection that is missing: a fresh set, a set whose
  # selection was just deleted, or a legacy transcript. The newest conversation
  # always becomes the selection.
  defp select_newest_fallback(%{conversations: conversations} = state) do
    newest =
      conversations |> Enum.max_by(fn {_id, %{updated_at: at}} -> at end, DateTime) |> elem(0)

    %{state | selected_id: newest}
  end

  defp fetch(conversations, id) when is_binary(id) do
    case Map.fetch(conversations, id) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :unknown_conversation}
    end
  end

  defp fetch(_conversations, _id), do: {:error, :unknown_conversation}

  defp new_title(title) when is_binary(title) do
    case title |> String.trim() |> cap_title() do
      "" -> @placeholder_title
      trimmed -> trimmed
    end
  end

  defp new_title(_title), do: @placeholder_title

  defp clean_title(title) when is_binary(title) do
    case title |> String.trim() |> cap_title() do
      "" -> {:error, :invalid_title}
      trimmed -> {:ok, trimmed}
    end
  end

  defp clean_title(_title), do: {:error, :invalid_title}

  defp cap_title(title) do
    title |> String.codepoints() |> Enum.take(@max_title_scalars) |> Enum.join()
  end

  defp or_placeholder(""), do: @placeholder_title
  defp or_placeholder(title), do: title

  defp legacy_title(%{messages: [%{role: :visitor, content: content} | _]}),
    do: title_for(content)

  defp legacy_title(_transcript), do: @placeholder_title

  defp snapshot_entries(conversations) do
    Enum.reduce_while(conversations, {:ok, %{}}, fn {id, entry}, {:ok, acc} ->
      case snapshot_entry(id, entry) do
        {:ok, snapshot} -> {:cont, {:ok, Map.put(acc, id, snapshot)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp snapshot_entry(id, %{transcript: transcript, title: title, updated_at: updated_at}) do
    with true <- valid_id?(id),
         {:ok, trimmed} <- clean_title(title),
         %DateTime{} <- updated_at,
         {:ok, transcript_snapshot} <- Transcript.snapshot(transcript) do
      {:ok,
       %{
         "title" => trimmed,
         "updated_at" => updated_at |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
         "transcript" => transcript_snapshot
       }}
    else
      _invalid -> :error
    end
  end

  defp snapshot_entry(_id, _entry), do: :error

  defp restore_entries(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn {id, entry}, {:ok, acc} ->
      case restore_entry(id, entry) do
        {:ok, restored} -> {:cont, {:ok, Map.put(acc, id, restored)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp restore_entry(id, %{
         "title" => title,
         "updated_at" => updated_at,
         "transcript" => transcript_snapshot
       }) do
    with true <- valid_id?(id),
         {:ok, trimmed} <- clean_title(title),
         {:ok, parsed, _offset} <- DateTime.from_iso8601(updated_at),
         {:ok, transcript} <- Transcript.restore(transcript_snapshot) do
      {:ok, %{transcript: transcript, title: trimmed, updated_at: parsed}}
    else
      _invalid -> :error
    end
  end

  defp restore_entry(_id, _entry), do: :error

  defp valid_id?(id) when is_binary(id), do: byte_size(id) in 1..@max_id_bytes
  defp valid_id?(_id), do: false

  defp random_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
