defmodule BnestApp.Codex.FixtureSession do
  @moduledoc false

  @behaviour BnestApp.Codex.Session

  @impl true
  def open(owner, _thread_id, _model, _reasoning_effort), do: {:ok, owner}

  @impl true
  def send_prompt(_owner, "Are you there?"), do: {:error, :closed}

  def send_prompt(_owner, _prompt), do: :ok

  @impl true
  def close(_session), do: :ok
end
