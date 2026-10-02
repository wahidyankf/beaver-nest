defmodule BnestApp.Test.CodexFixtureSession do
  @moduledoc false

  use Boundary, top_level?: true, check: [in: false, out: false]

  @behaviour BnestApp.CodexChat.Ports.AgentSession

  # The integration agent session starts no Codex. Each `open` and `send_prompt` is reported
  # as `{:codex_fixture_session, call}` to the processes that started the caller (a LiveView
  # test's `$callers`, the test itself), never to the owner, whose LiveView handles only
  # session events. The test then answers only a prompt the session really received.

  @impl true
  def open(owner, thread_id, model, reasoning_effort, repository_mode) do
    report({:open, owner, {thread_id, model, reasoning_effort, repository_mode}})

    if thread_id == "unavailable-thread", do: {:error, :not_found}, else: {:ok, owner}
  end

  @impl true
  def send_prompt(owner, prompt) do
    report({:prompt, owner, prompt})

    if prompt == "Are you there?", do: {:error, :closed}, else: :ok
  end

  @impl true
  def close(_session), do: :ok

  defp report(call) do
    for caller <- Process.get(:"$callers", []), do: send(caller, {:codex_fixture_session, call})
    :ok
  end
end
