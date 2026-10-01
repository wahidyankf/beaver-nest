defmodule BnestApp.Test.InMemory.AgentSession do
  @moduledoc """
  A recording `BnestApp.CodexChat.Ports.AgentSession`. It starts no Codex runner: every call
  is reported to the session's owner with `send/2`, so a test asserts on its own mailbox.

  Like the integration fixture session, it cannot resume the thread `"unavailable-thread"`
  and reports a closed session for the prompt `"Are you there?"`. It also refuses every
  conversation for the model `"unavailable-model"`, so a test can make Codex unavailable.
  """

  @behaviour BnestApp.CodexChat.Ports.AgentSession

  @impl true
  def open(owner, thread_id, model, reasoning_effort, repository_mode) do
    send(owner, {:agent_session, :open, {thread_id, model, reasoning_effort, repository_mode}})

    cond do
      model == "unavailable-model" -> {:error, :unavailable}
      thread_id == "unavailable-thread" -> {:error, :not_found}
      true -> {:ok, %{owner: owner, thread_id: thread_id, ref: make_ref()}}
    end
  end

  @impl true
  def send_prompt(%{owner: owner} = session, prompt) do
    send(owner, {:agent_session, :prompt, session, prompt})
    if prompt == "Are you there?", do: {:error, :closed}, else: :ok
  end

  @impl true
  def close(%{owner: owner} = session) do
    send(owner, {:agent_session, :close, session})
    :ok
  end

  def close(_failed_or_absent_session), do: :ok
end
