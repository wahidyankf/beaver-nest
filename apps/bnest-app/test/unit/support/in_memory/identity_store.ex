defmodule BnestApp.Test.InMemory.IdentityStore do
  @moduledoc """
  An Agent-backed `BnestApp.Identity.Ports.IdentityStore`. It keeps the port's put, replace
  and exact-removal semantics without schema validation. Each handle owns its own agent, so
  tests that start their own stores may run concurrently.
  """

  @behaviour BnestApp.Identity.Ports.IdentityStore

  @doc "A fresh, empty store linked to the calling test."
  def start do
    {:ok, pid} = Agent.start_link(fn -> %{} end)
    %{adapter: __MODULE__, pid: pid}
  end

  @doc "Every stored record, keyed by `{kind, identity}`."
  def snapshot(%{pid: pid}), do: Agent.get(pid, & &1)

  # The in-memory store keeps its own records and cannot wrap Storage's record store, so it
  # must never be configured as the `:identity_store` adapter: answering here with a fresh,
  # empty store would hide every record the test wrote behind a silent `:open` setup.
  @dialyzer {:nowarn_function, new: 1}
  @impl true
  def new(_record_store) do
    raise ArgumentError,
          "#{inspect(__MODULE__)} cannot wrap a record store; start/0 a store and pass its " <>
            "handle (for example as the Identity `store:` option) instead of configuring it " <>
            "as the :identity_store adapter"
  end

  @impl true
  def read_account(store, user_id), do: read(store, {:account, user_id})

  @impl true
  def read_username(store, username), do: read(store, {:username_index, username})

  @impl true
  def read_session(store, digest), do: read(store, {:session, digest})

  @impl true
  def read_bootstrap(store), do: read(store, {:bootstrap, nil})

  @impl true
  def put_account(store, account), do: put_new(store, {:account, account["userId"]}, account)

  @impl true
  def put_username(store, index),
    do: put_new(store, {:username_index, index["normalizedUsername"]}, index)

  @impl true
  def put_session(store, session),
    do: put_new(store, {:session, session["tokenDigest"]}, session)

  @impl true
  def put_bootstrap(store, journal), do: put_new(store, {:bootstrap, nil}, journal)

  @impl true
  def replace_account(store, account),
    do: replace(store, {:account, account["userId"]}, account)

  @impl true
  def replace_session(store, session),
    do: replace(store, {:session, session["tokenDigest"]}, session)

  @impl true
  def replace_bootstrap(store, journal), do: replace(store, {:bootstrap, nil}, journal)

  @impl true
  def remove_account(store, account),
    do: remove_exact(store, {:account, account["userId"]}, account)

  @impl true
  def remove_username(store, index),
    do: remove_exact(store, {:username_index, index["normalizedUsername"]}, index)

  @impl true
  def remove_bootstrap(store, journal), do: remove_exact(store, {:bootstrap, nil}, journal)

  @impl true
  def empty?(store) do
    not Enum.any?(snapshot(store), fn {{kind, _identity}, _record} ->
      kind in [:account, :username_index]
    end)
  end

  @impl true
  def lock_key(%{pid: pid}), do: {__MODULE__, pid}

  defp read(%{pid: pid}, key) do
    case Agent.get(pid, &Map.fetch(&1, key)) do
      {:ok, record} -> {:ok, record}
      :error -> {:error, :missing}
    end
  end

  defp put_new(%{pid: pid}, key, record) do
    Agent.get_and_update(pid, fn records ->
      if Map.has_key?(records, key),
        do: {{:error, :exists}, records},
        else: {{:ok, record}, Map.put(records, key, record)}
    end)
  end

  defp replace(%{pid: pid}, key, record) do
    Agent.get_and_update(pid, fn records ->
      if Map.has_key?(records, key),
        do: {{:ok, record}, Map.put(records, key, record)},
        else: {{:error, :missing}, records}
    end)
  end

  defp remove_exact(%{pid: pid}, key, expected) do
    Agent.get_and_update(pid, fn records ->
      case Map.fetch(records, key) do
        {:ok, ^expected} -> {:ok, Map.delete(records, key)}
        {:ok, _changed} -> {{:error, :changed}, records}
        :error -> {:ok, records}
      end
    end)
  end
end
