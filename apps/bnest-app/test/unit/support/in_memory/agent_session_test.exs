defmodule BnestApp.Test.InMemory.AgentSessionTest do
  # The recording agent-session double refuses a workspace-write open while
  # the scenario flags the refusal, so a write-enable fails closed.
  #
  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A failed write-enable stays read-only and says so
  use ExUnit.Case, async: false

  alias BnestApp.Test.InMemory.AgentSession, as: InMemoryAgentSession

  setup do
    previous = Application.get_env(:bnest_app, :refuse_workspace_write)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:bnest_app, :refuse_workspace_write),
        else: Application.put_env(:bnest_app, :refuse_workspace_write, previous)
    end)

    :ok
  end

  test "opens a workspace-write session by default" do
    Application.delete_env(:bnest_app, :refuse_workspace_write)

    assert {:ok, _session} =
             InMemoryAgentSession.open(self(), nil, "gpt-6.1-terra", "medium", :workspace_write)
  end

  test "refuses a workspace-write open while the refusal is flagged" do
    Application.put_env(:bnest_app, :refuse_workspace_write, true)

    assert {:error, :write_unavailable} =
             InMemoryAgentSession.open(self(), nil, "gpt-6.1-terra", "medium", :workspace_write)

    assert_receive {:agent_session, :open, {nil, "gpt-6.1-terra", "medium", :workspace_write}}
  end
end
