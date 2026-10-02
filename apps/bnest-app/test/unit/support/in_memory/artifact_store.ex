defmodule BnestApp.Test.InMemory.ArtifactStore do
  @moduledoc """
  An Agent-backed `BnestApp.Backup.Ports.ArtifactStore`: backup destinations' directories
  and files kept as terms, with each file's mode and whether it was flushed. A file's
  digest and size are those of its term. It reaches no disk.

  The unit layer configures this module as Backup's `:artifact_store`; its `new/0` serves
  the store a test started with `install/0`, which the test supervisor stops before the
  next test. The test seams `put_file/3`, `put_symlink/2` and `put_unavailable/2` stand in
  for files and links nothing in Backup writes, and for a directory that cannot be created;
  `file/2`, `directory/2`, `directories/1` and `paths/2` read back what the store holds.
  """

  @behaviour BnestApp.Backup.Ports.ArtifactStore

  alias BnestApp.Backup.Domain.Location

  @doc """
  Starts a fresh store under the calling test's supervisor as the store `new/0` serves,
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
              "no in-memory artifact store is installed; call #{inspect(__MODULE__)}.install/0 " <>
                "in the test before reaching BnestApp.Backup"

      pid ->
        %{adapter: __MODULE__, pid: pid}
    end
  end

  @doc "Stores `content` at `path`, readable by anyone and not flushed, as an unknown file."
  def put_file(%{pid: pid}, path, content) do
    Agent.update(pid, &put_in(&1.files[path], %{content: content, mode: 0o644, synced?: false}))
  end

  @doc "Makes `path` a symbolic link."
  def put_symlink(%{pid: pid}, path),
    do: Agent.update(pid, &%{&1 | symlinks: [path | &1.symlinks]})

  @doc "Makes `directory` one that cannot be created."
  def put_unavailable(%{pid: pid}, directory),
    do: Agent.update(pid, &%{&1 | unavailable: [directory | &1.unavailable]})

  @doc "The file at `path` (`content`, `mode`, `synced?`), or nil."
  def file(%{pid: pid}, path), do: Agent.get(pid, & &1.files[path])

  @doc "The directory at `path` (its `mode`), or nil."
  def directory(%{pid: pid}, path), do: Agent.get(pid, & &1.directories[path])

  @doc "Every directory created, in path order."
  def directories(%{pid: pid}), do: Agent.get(pid, &(&1.directories |> Map.keys() |> Enum.sort()))

  @doc "The path of every file under `directory`, in path order."
  def paths(%{pid: pid}, directory) do
    Agent.get(pid, fn state ->
      state.files |> Map.keys() |> Enum.filter(&under?(&1, directory)) |> Enum.sort()
    end)
  end

  @impl true
  def symlink_in_path?(%{pid: pid}, path),
    do:
      Agent.get(pid, fn state -> Enum.any?(state.symlinks, &(path == &1 or under?(path, &1))) end)

  @impl true
  def prepare_directory(%{pid: pid}, directory) do
    Agent.get_and_update(pid, fn state ->
      if directory in state.unavailable,
        do: {{:error, :unavailable}, state},
        else: {:ok, put_in(state.directories[directory], %{mode: 0o700})}
    end)
  end

  @impl true
  def read_marker(store, directory) do
    case file(store, Location.marker_path(directory)) do
      nil -> {:error, :absent}
      %{content: marker} -> {:ok, marker}
    end
  end

  @impl true
  def write_marker(%{pid: pid}, directory, marker),
    do: Agent.update(pid, &put_private(&1, Location.marker_path(directory), marker, false))

  @impl true
  def remove(%{pid: pid}, path), do: Agent.update(pid, &%{&1 | files: Map.delete(&1.files, path)})

  @impl true
  def restrict(store, path), do: update_file!(store, path, &%{&1 | mode: 0o600})

  @impl true
  def sync(store, path), do: update_file!(store, path, &%{&1 | synced?: true})

  @impl true
  def promote(%{pid: pid}, from, to) do
    Agent.update(pid, fn state ->
      {file, files} = Map.pop(state.files, from)
      file || raise ArgumentError, "no file at #{from}"
      %{state | files: Map.put(files, to, file)}
    end)
  end

  @impl true
  def digest(store, path),
    do: :crypto.hash(:sha256, bytes!(store, path)) |> Base.encode16(case: :lower)

  @impl true
  def size(store, path), do: byte_size(bytes!(store, path))

  @impl true
  def regular?(store, path), do: file(store, path) != nil

  @impl true
  def write_receipt(%{pid: pid}, path, receipt),
    do: Agent.update(pid, &put_private(&1, path, receipt, true))

  @impl true
  def receipts(%{pid: pid}, directory) do
    Agent.get(pid, fn state ->
      for {path, %{content: receipt}} <- Enum.sort(state.files),
          child?(path, directory) and String.ends_with?(path, ".receipt.json"),
          do: receipt
    end)
  end

  defp empty, do: %{directories: %{}, files: %{}, symlinks: [], unavailable: []}

  defp put_private(state, path, content, synced?),
    do: put_in(state.files[path], %{content: content, mode: 0o600, synced?: synced?})

  defp update_file!(%{pid: pid}, path, fun) do
    Agent.update(pid, fn state ->
      Map.has_key?(state.files, path) || raise ArgumentError, "no file at #{path}"
      update_in(state.files[path], fun)
    end)
  end

  defp bytes!(store, path) do
    case file(store, path) do
      nil -> raise ArgumentError, "no file at #{path}"
      %{content: content} -> :erlang.term_to_binary(content)
    end
  end

  defp under?(path, directory), do: String.starts_with?(path, directory <> "/")

  defp child?(path, directory),
    do:
      under?(path, directory) and
        not String.contains?(String.replace_prefix(path, directory <> "/", ""), "/")
end
