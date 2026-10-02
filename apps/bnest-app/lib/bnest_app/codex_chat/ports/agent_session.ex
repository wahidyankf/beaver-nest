defmodule BnestApp.CodexChat.Ports.AgentSession do
  @moduledoc """
  A live conversation with the Codex agent on behalf of one owner process.

  `open/5` starts a session for the owner, resuming `thread_id` when it is not `nil`, with the
  model, reasoning effort and repository access mode. The session reports to the owner as
  `{:codex, session, event}` messages, where `session` is the term `open/5` returned and
  `event` is one of `{:thread_started, thread_id}`, `{:assistant_update, item_id, text}`,
  `{:assistant_update, text}`, `{:reasoning_update, item_id, text}`,
  `{:activity_update, item_id, text}`, `:turn_completed`, `{:error, message}` or
  `{:resume_failed, message}`.

  A session that can no longer reach the agent refuses `send_prompt/2` with
  `{:error, :closed}` until it is closed.
  """

  alias BnestApp.CodexChat.Domain.RepositoryAccess

  @callback open(pid(), String.t() | nil, String.t(), String.t(), RepositoryAccess.mode()) ::
              {:ok, term()} | {:error, term()}
  @callback send_prompt(term(), String.t()) :: :ok | {:error, term()}
  @callback close(term()) :: :ok
end
