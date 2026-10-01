defmodule BnestApp.Test.InMemory.RecordBackend do
  @moduledoc """
  An Agent-backed `BnestApp.Storage.Ports.RecordBackend`. It keeps the port's revision and
  exact-removal semantics without schema validation, and it can fail its next write on
  request so a test can exercise the retry paths.
  """

  @behaviour BnestApp.Storage.Ports.RecordBackend

  def start do
    {:ok, pid} = Agent.start_link(fn -> %{} end)
    %{backend: __MODULE__, pid: pid}
  end

  def snapshot(%{pid: pid}), do: Agent.get(pid, & &1)

  def fail_next_write(%{pid: pid}) do
    Agent.update(pid, &Map.put(&1, :fail_next_write, true))
  end

  @impl true
  def identity_files_empty?(store) do
    not Enum.any?(snapshot(store), fn
      {{type, _identity}, _record} when type in [:account, :username_index] -> true
      _other -> false
    end)
  end

  @impl true
  def read(%{pid: pid}, type, identity) do
    Agent.get(pid, fn records -> Map.fetch(records, {type, identity}) end)
    |> case do
      {:ok, record} -> {:ok, record}
      :error -> {:error, :missing}
    end
  end

  @impl true
  def write(%{pid: pid}, type, identity, expected_revision, candidate) do
    Agent.get_and_update(pid, fn records ->
      key = {type, identity}
      existing = Map.get(records, key)
      actual_revision = if existing, do: existing["revision"], else: nil

      cond do
        Map.get(records, :fail_next_write, false) ->
          {{:error, :injected_failure}, Map.delete(records, :fail_next_write)}

        actual_revision == expected_revision ->
          prepared = Map.put(candidate, "revision", (actual_revision || -1) + 1)
          {{:ok, prepared}, Map.put(records, key, prepared)}

        true ->
          {{:error, :stale}, records}
      end
    end)
  end

  @impl true
  def put_new(%{pid: pid}, type, identity, candidate) do
    Agent.get_and_update(pid, fn records ->
      key = {type, identity}

      if Map.has_key?(records, key),
        do: {{:error, :exists}, records},
        else: {{:ok, candidate}, Map.put(records, key, candidate)}
    end)
  end

  @impl true
  def replace(%{pid: pid}, type, identity, candidate) do
    Agent.get_and_update(pid, fn records ->
      key = {type, identity}

      if Map.has_key?(records, key),
        do: {{:ok, candidate}, Map.put(records, key, candidate)},
        else: {{:error, :missing}, records}
    end)
  end

  @impl true
  def remove_exact(%{pid: pid}, type, identity, expected) do
    Agent.get_and_update(pid, fn records ->
      key = {type, identity}

      case Map.fetch(records, key) do
        {:ok, ^expected} -> {:ok, Map.delete(records, key)}
        {:ok, _changed} -> {{:error, :changed}, records}
        :error -> {:ok, records}
      end
    end)
  end
end
