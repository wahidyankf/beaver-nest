defmodule BnestApp.Test.InMemory.IgnoreCheck do
  @moduledoc """
  An Agent-backed `BnestApp.Backup.Ports.IgnoreCheck`: a repository that ignores every path
  unless a test says otherwise. It runs no git.

  The unit layer configures this module as Backup's `:ignore_check`; its `new/0` serves the
  check a test started with `install/0`, which the test supervisor stops before the next
  test. `put_ignored/2` sets the answer; `checks/1` reports every `{repository_root,
  relative_path}` asked about.
  """

  @behaviour BnestApp.Backup.Ports.IgnoreCheck

  @doc """
  Starts a fresh check under the calling test's supervisor as the one `new/0` serves,
  replacing one this test installed before, and returns its handle.
  """
  def install do
    if GenServer.whereis(__MODULE__), do: ExUnit.Callbacks.stop_supervised!(__MODULE__)

    ExUnit.Callbacks.start_supervised!(%{
      id: __MODULE__,
      start: {Agent, :start_link, [fn -> %{ignored?: true, checks: []} end, [name: __MODULE__]]}
    })

    new()
  end

  @impl true
  def new do
    case GenServer.whereis(__MODULE__) do
      nil ->
        raise ArgumentError,
              "no in-memory ignore check is installed; call #{inspect(__MODULE__)}.install/0 " <>
                "in the test before reaching BnestApp.Backup"

      pid ->
        %{adapter: __MODULE__, pid: pid}
    end
  end

  @doc "Makes the repository ignore (`true`) or track (`false`) every path."
  def put_ignored(%{pid: pid}, ignored?) when is_boolean(ignored?),
    do: Agent.update(pid, &%{&1 | ignored?: ignored?})

  @doc "Every `{repository_root, relative_path}` checked, oldest first."
  def checks(%{pid: pid}), do: Agent.get(pid, &Enum.reverse(&1.checks))

  @impl true
  def ignored?(%{pid: pid}, repository_root, relative_path) do
    Agent.get_and_update(pid, fn state ->
      {state.ignored?, %{state | checks: [{repository_root, relative_path} | state.checks]}}
    end)
  end
end
