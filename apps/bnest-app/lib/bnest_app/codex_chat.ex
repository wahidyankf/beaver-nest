defmodule BnestApp.CodexChat do
  @moduledoc """
  The Codex chat bounded context: each user's conversation with the local Codex agent, its
  saved transcript, and the models the agent offers.

  This module is the context's application-service facade. Its adapters come from
  application configuration under `config :bnest_app, BnestApp.CodexChat`, one per port in
  `BnestApp.CodexChat.Ports`, so a test can supply doubles. Functions that reach a port take
  an optional `store:` transcript-store handle or `agent_session:` module; without one they
  use the configured adapter. The transcript and model rules are the exported, pure
  `BnestApp.CodexChat.Domain`, which callers use to render and edit a transcript.

  A conversation is opened for the calling process, which receives the session's
  `{:codex, session, event}` messages (see `BnestApp.CodexChat.Ports.AgentSession`) and
  passes each event to `apply_event/2`.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [Logger],
    exports: [{Domain, []}, {Ports, []}]

  alias BnestApp.CodexChat.Domain.{ModelAccess, RepositoryAccess, Settings, Transcript}
  alias BnestApp.CodexChat.Domain.TranscriptRecord
  alias BnestApp.CodexChat.ModelCatalog
  alias BnestApp.CodexChat.Ports.TranscriptStore

  @unavailable "Codex is not available."
  @fresh_conversation "The previous Codex conversation was unavailable. Your transcript is preserved in a fresh conversation."
  @interrupted "The previous response was interrupted. Your transcript is preserved; send a new message to continue."
  @stale "Newer chat data exists. Reload before continuing."
  @unsaved "Chat could not be saved. Your previous saved chat is unchanged."

  @type option ::
          {:store, TranscriptStore.handle()} | {:agent_session, module()} | {:now, DateTime.t()}
  @type session :: term()

  @doc """
  The configured adapter for a Codex chat port: `:agent_session`, `:model_discovery` or
  `:transcript_store`.
  """
  @spec adapter(atom()) :: module()
  def adapter(port), do: :bnest_app |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(port)

  @doc "The context's processes, for the application supervisor to start."
  @spec child_specs() :: [Supervisor.child_spec() | module()]
  def child_specs, do: [ModelCatalog]

  @doc "Every model the local Codex agent offers."
  @spec models() :: [ModelCatalog.model()]
  def models, do: ModelCatalog.all()

  @doc "Which of the offered models `user` may use, and whether they may pick among them."
  @spec model_access(map()) :: ModelAccess.access()
  def model_access(user), do: ModelAccess.resolve(user, models())

  @doc """
  The reasoning effort to use with `model`: `requested` when the model supports it, else the
  preferred effort, else the model's default.
  """
  @spec reasoning_effort(ModelCatalog.model(), String.t()) :: String.t()
  def reasoning_effort(model, requested \\ Settings.preferred_reasoning_effort()),
    do: ModelCatalog.reasoning_effort(model, requested)

  @doc """
  The transcript `owner_id` saved last, with its stored record. The store's error is
  returned as is (`{:error, :missing}` when they saved none), and `{:error, :unrestorable}`
  when the stored state is no transcript.
  """
  @spec load_transcript(String.t(), [option()]) ::
          {:ok, Transcript.t(), map()} | {:error, atom()}
  def load_transcript(owner_id, options \\ []) do
    with {:ok, record} <- TranscriptStore.read(store(options), owner_id) do
      case Transcript.restore(record["state"]) do
        {:ok, transcript} -> {:ok, transcript, record}
        :error -> {:error, :unrestorable}
      end
    end
  end

  @doc """
  Saves `transcript` as the `chat` record of `owner_id` over `previous`, the record it last
  loaded or saved (`nil` for none), and returns the stored record.

  The write expects the revision of `previous`, so a chat that changed in between is kept.
  A failed write returns the transcript failed with the message to show; a transcript that
  has no valid snapshot is not saved and returns `:error`. The record is stamped with the
  `now:` option, the current time by default, truncated to the second.
  """
  @spec save_transcript(String.t(), Transcript.t(), map() | nil, [option()]) ::
          {:ok, map()} | {:error, Transcript.t()} | :error
  def save_transcript(owner_id, transcript, previous, options \\ []) do
    with {:ok, snapshot} <- Transcript.snapshot(transcript) do
      now = Keyword.get_lazy(options, :now, &DateTime.utc_now/0)

      case TranscriptStore.write(
             store(options),
             owner_id,
             TranscriptRecord.expected_revision(previous),
             TranscriptRecord.record(owner_id, snapshot, previous, now)
           ) do
        {:ok, record} -> {:ok, record}
        {:error, :stale} -> {:error, Transcript.fail(transcript, @stale)}
        {:error, _reason} -> {:error, Transcript.fail(transcript, @unsaved)}
      end
    end
  end

  @doc """
  Opens a Codex conversation for the calling process with the transcript's model and
  reasoning effort, resuming its thread.

  Returns `{:ok, session, transcript}` when it opened; `{:fresh, session, transcript}` when
  the saved thread could not be resumed and a fresh conversation keeps the transcript, which
  the caller should save; and `{:error, transcript}` with the transcript failed when Codex is
  unavailable.
  """
  @spec open_conversation(Transcript.t(), RepositoryAccess.mode(), [option()]) ::
          {:ok | :fresh, session(), Transcript.t()} | {:error, Transcript.t()}
  def open_conversation(transcript, repository_mode, options \\ []) do
    agent_session = agent_session(options)

    case open(agent_session, transcript, transcript.thread_id, repository_mode) do
      {:ok, session} ->
        {:ok, session, transcript}

      {:error, _reason} when not is_nil(transcript.thread_id) ->
        fresh = %{transcript | thread_id: nil, error: @fresh_conversation}

        case open(agent_session, fresh, nil, repository_mode) do
          {:ok, session} -> {:fresh, session, fresh}
          {:error, _reason} -> {:error, Transcript.fail(fresh, @unavailable)}
        end

      {:error, _reason} ->
        {:error, Transcript.fail(transcript, @unavailable)}
    end
  end

  @doc """
  Replaces `session`, whose thread could not be resumed, with a fresh conversation that keeps
  the transcript. Returns the new session and the transcript to save, or the transcript failed
  when Codex is unavailable.
  """
  @spec replace_conversation(session(), Transcript.t(), RepositoryAccess.mode(), [option()]) ::
          {:ok, session(), Transcript.t()} | {:error, Transcript.t()}
  def replace_conversation(session, transcript, repository_mode, options \\ []) do
    agent_session = agent_session(options)
    agent_session.close(session)
    fresh = %{Transcript.fail(transcript, @fresh_conversation) | thread_id: nil}

    case open(agent_session, fresh, nil, repository_mode) do
      {:ok, replacement} -> {:ok, replacement, fresh}
      {:error, _reason} -> {:error, Transcript.fail(fresh, @unavailable)}
    end
  end

  @doc """
  The turn a reopened conversation still owes: `{:resend, prompt, transcript}` to send once
  more, `:none`, or `{:interrupted, transcript}` failed when it was already resent.
  """
  @spec recover_pending_turn(Transcript.t()) ::
          {:resend, String.t(), Transcript.t()} | :none | {:interrupted, Transcript.t()}
  def recover_pending_turn(transcript) do
    case Transcript.continuation_prompt(transcript) do
      {:ok, prompt, resent} -> {:resend, prompt, resent}
      {:error, :none} -> :none
      {:error, :already_attempted} -> {:interrupted, Transcript.fail(transcript, @interrupted)}
    end
  end

  @doc """
  Sends `prompt` to the conversation. Returns `transcript` unchanged when Codex took it, or
  failed when Codex is unavailable.
  """
  @spec send_prompt(session(), Transcript.t(), String.t(), [option()]) ::
          {:ok, Transcript.t()} | {:error, Transcript.t()}
  def send_prompt(session, transcript, prompt, options \\ []) do
    case agent_session(options).send_prompt(session, prompt) do
      :ok -> {:ok, transcript}
      {:error, _reason} -> {:error, Transcript.fail(transcript, @unavailable)}
    end
  end

  @doc "Closes the conversation."
  @spec close(session(), [option()]) :: :ok
  def close(session, options \\ []), do: agent_session(options).close(session)

  @doc """
  Applies a session event to the transcript. A new thread, a completed turn and an error
  return `{:persist, transcript}`, to save now; streamed answer and progress updates return
  `{:checkpoint, transcript}`, to save soon; any other event is `:ignore`d.
  """
  @spec apply_event(Transcript.t(), term()) ::
          {:persist | :checkpoint, Transcript.t()} | :ignore
  def apply_event(transcript, {:thread_started, thread_id}),
    do: {:persist, Transcript.put_thread_id(transcript, thread_id)}

  def apply_event(transcript, {:assistant_update, item_id, text}),
    do: {:checkpoint, Transcript.update_assistant(transcript, item_id, text)}

  def apply_event(transcript, {:assistant_update, text}),
    do: {:checkpoint, Transcript.update_assistant(transcript, text)}

  def apply_event(transcript, {:reasoning_update, item_id, text}),
    do: {:checkpoint, Transcript.update_progress(transcript, item_id, :reasoning, text)}

  def apply_event(transcript, {:activity_update, item_id, text}),
    do: {:checkpoint, Transcript.update_progress(transcript, item_id, :activity, text)}

  def apply_event(transcript, :turn_completed), do: {:persist, Transcript.complete(transcript)}

  def apply_event(transcript, {:error, message}),
    do: {:persist, Transcript.fail(transcript, message)}

  def apply_event(_transcript, _event), do: :ignore

  defp open(agent_session, transcript, thread_id, repository_mode) do
    agent_session.open(
      self(),
      thread_id,
      transcript.model,
      transcript.reasoning_effort,
      repository_mode
    )
  end

  defp agent_session(options),
    do: Keyword.get_lazy(options, :agent_session, fn -> adapter(:agent_session) end)

  defp store(options),
    do: Keyword.get_lazy(options, :store, fn -> adapter(:transcript_store).new() end)
end
