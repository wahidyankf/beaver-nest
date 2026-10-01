defmodule BnestApp.Test.CodexFixtureSession do
  @moduledoc false

  use Boundary, top_level?: true, check: [in: false, out: false]

  @behaviour BnestApp.CodexChat.Ports.AgentSession

  @impl true
  def open(_owner, "unavailable-thread", _model, _reasoning_effort, _repository_mode),
    do: {:error, :not_found}

  def open(owner, _thread_id, _model, _reasoning_effort, _repository_mode), do: {:ok, owner}

  @impl true
  def send_prompt(_owner, "Are you there?"), do: {:error, :closed}

  def send_prompt(_owner, _prompt), do: :ok

  @impl true
  def close(_session), do: :ok
end
