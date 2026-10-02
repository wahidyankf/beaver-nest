defmodule BnestApp.Test.InMemory.BackupConfigStore do
  @moduledoc """
  An Agent-backed `BnestApp.Backup.Ports.ConfigStore`: the backup configuration document
  kept as a term, for a synthetic repository under `/srv/test-user-backup`. It never reads
  or writes a configuration file, so the unit layer cannot reach the operator's
  `~/.config/bnest/backup.json`.

  The unit layer configures this module as Backup's `:config_store`; its `new/0` serves the
  store a test started with `install/0`, which the test supervisor stops before the next
  test. `put_document/2`, `put_read_error/2` and `put_write_error/1` set what a read or a
  write meets; `document/1` and `writes/1` report what Backup stored.
  """

  @behaviour BnestApp.Backup.Ports.ConfigStore

  @config_path "/srv/test-user-backup/configuration/backup.json"
  @repository_root "/srv/test-user-backup/repository"

  @doc """
  Starts a fresh store under the calling test's supervisor as the one `new/0` serves,
  replacing one this test installed before, and returns its handle.
  """
  def install do
    if GenServer.whereis(__MODULE__), do: ExUnit.Callbacks.stop_supervised!(__MODULE__)

    ExUnit.Callbacks.start_supervised!(%{
      id: __MODULE__,
      start: {Agent, :start_link, [&empty/0, [name: __MODULE__]]}
    })

    new()
  end

  @impl true
  def new do
    case GenServer.whereis(__MODULE__) do
      nil ->
        raise ArgumentError,
              "no in-memory backup configuration store is installed; call " <>
                "#{inspect(__MODULE__)}.install/0 in the test before reaching BnestApp.Backup"

      pid ->
        %{adapter: __MODULE__, pid: pid}
    end
  end

  @doc "Stores `document` as is, whatever its shape."
  def put_document(%{pid: pid}, document), do: Agent.update(pid, &%{&1 | document: document})

  @doc "Makes every read fail with `reason`."
  def put_read_error(%{pid: pid}, reason), do: Agent.update(pid, &%{&1 | read_error: reason})

  @doc "Makes every write fail."
  def put_write_error(%{pid: pid}), do: Agent.update(pid, &%{&1 | write_error?: true})

  @doc "The stored document, or nil."
  def document(%{pid: pid}), do: Agent.get(pid, & &1.document)

  @doc "Every document written, oldest first."
  def writes(%{pid: pid}), do: Agent.get(pid, &Enum.reverse(&1.writes))

  @impl true
  def read(%{pid: pid}) do
    Agent.get(pid, fn
      %{read_error: reason} when reason != nil -> {:error, reason}
      %{document: nil} -> {:error, :absent}
      %{document: document} -> {:ok, document}
    end)
  end

  @impl true
  def write(%{pid: pid}, document) do
    Agent.get_and_update(pid, fn
      %{write_error?: true} = state -> {{:error, :config_write_failed}, state}
      state -> {:ok, %{state | document: document, writes: [document | state.writes]}}
    end)
  end

  @impl true
  def config_path(_store), do: @config_path

  @impl true
  def repository_root(_store), do: @repository_root

  defp empty, do: %{document: nil, read_error: nil, write_error?: false, writes: []}
end
