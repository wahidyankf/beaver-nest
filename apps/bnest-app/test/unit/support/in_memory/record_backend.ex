defmodule BnestApp.Test.InMemory.RecordBackend do
  @moduledoc """
  An Agent-backed `BnestApp.Storage.Ports.RecordBackend`. It keeps the port's revision and
  exact-removal semantics without schema validation, and it can fail its next write on
  request so a test can exercise the retry paths.

  A store started with an observer reports every record operation to that process as
  `{:record_access, operation, type, identity}`, whichever process performs it, so a test
  can see which records a request touched.
  """

  @behaviour BnestApp.Storage.Ports.RecordBackend

  def start(observer \\ nil) do
    {:ok, pid} = Agent.start_link(fn -> %{} end)
    %{backend: __MODULE__, pid: pid, observer: observer}
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
  def read(%{pid: pid} = store, type, identity) do
    observe(store, :read, type, identity)

    Agent.get(pid, fn records -> Map.fetch(records, {type, identity}) end)
    |> case do
      {:ok, record} -> {:ok, record}
      :error -> {:error, :missing}
    end
  end

  @impl true
  def write(%{pid: pid} = store, type, identity, expected_revision, candidate) do
    observe(store, :write, type, identity)

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
  def put_new(%{pid: pid} = store, type, identity, candidate) do
    observe(store, :put_new, type, identity)

    Agent.get_and_update(pid, fn records ->
      key = {type, identity}

      if Map.has_key?(records, key),
        do: {{:error, :exists}, records},
        else: {{:ok, candidate}, Map.put(records, key, candidate)}
    end)
  end

  @impl true
  def replace(%{pid: pid} = store, type, identity, candidate) do
    observe(store, :replace, type, identity)

    Agent.get_and_update(pid, fn records ->
      key = {type, identity}

      if Map.has_key?(records, key),
        do: {{:ok, candidate}, Map.put(records, key, candidate)},
        else: {{:error, :missing}, records}
    end)
  end

  @impl true
  def remove_exact(%{pid: pid} = store, type, identity, expected) do
    observe(store, :remove_exact, type, identity)

    Agent.get_and_update(pid, fn records ->
      key = {type, identity}

      case Map.fetch(records, key) do
        {:ok, ^expected} -> {:ok, Map.delete(records, key)}
        {:ok, _changed} -> {{:error, :changed}, records}
        :error -> {:ok, records}
      end
    end)
  end

  defp observe(%{observer: observer}, operation, type, identity) when is_pid(observer),
    do: send(observer, {:record_access, operation, type, identity})

  defp observe(_store, _operation, _type, _identity), do: :ok
end
