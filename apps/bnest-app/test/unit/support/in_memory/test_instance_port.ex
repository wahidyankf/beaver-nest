defmodule BnestApp.Test.InMemory.TestInstancePort do
  @moduledoc """
  The unit layer's test-side port for the test instance lifecycle (ADR 001, sections 1 and 2).

  It is a pure model, not a database. It keeps the current instance, the directories, the storage
  pointer, the backup configuration and the database file the switch would create, and the accounts,
  messages, records and sessions a seed would write. Every path comes from
  `BnestApp.TestInstance.Paths.derive/4` and every seed is checked by `BnestApp.TestInstance.Seed.validate/2`,
  so the refusals are the production rules. It never models SQLite, so a unit scenario that asks what the
  database holds is answered by this model; the integration layer reads the real file.

  The spawn order is the switch's: create, migrate, seed. A failure at a step, or an injected failure
  after it, undoes everything the spawn made, as `BnestApp.TestInstance` does.
  """

  alias BnestApp.Test.InMemory.CredentialHasher
  alias BnestApp.TestInstance.Paths
  alias BnestApp.TestInstance.Seed

  @run_id "unit-run"
  @flat_root "/synthetic/unit/data/test/runs/unit-run"
  @sqlite_root "/synthetic/unit/sqlite/test/runs/unit-run"

  defstruct current: nil, directories: [], pointer: nil, backup_config: nil, database_files: []

  @type t :: %__MODULE__{}

  @doc "A port with no instance."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "The current instance's id and generation, or nil, as `GET /state` reports them."
  @spec current(t()) :: %{instance_id: String.t(), generation: String.t()} | nil
  def current(%__MODULE__{current: nil}), do: nil

  def current(%__MODULE__{current: current}),
    do: %{instance_id: current.instance_id, generation: current.generation}

  @doc """
  Spawns an instance with `opts`: `:instance_id`, `:phase`, `:seed` (a seed map, optional) and
  `:fail_after` (a step name, optional). Returns `{:ok, port, observation}` or `{:error, port, refusal}`,
  where a refused spawn leaves the port as it was before the call.
  """
  @spec spawn(t(), keyword()) :: {:ok, t(), map()} | {:error, t(), map()}
  def spawn(%__MODULE__{current: nil} = port, opts) do
    instance_id = Keyword.fetch!(opts, :instance_id)

    case Paths.derive(@flat_root, @sqlite_root, @run_id, instance_id) do
      {:ok, paths} -> run_steps(port, paths, opts)
      {:error, reason} -> {:error, port, %{step: :create, reason: reason}}
    end
  end

  def spawn(%__MODULE__{} = port, _opts), do: {:error, port, %{reason: :instance_active}}

  @doc "Drops the current instance when `instance_id` names it; otherwise `{:error, port, :not_current}`."
  @spec drop(t(), String.t()) :: {:ok, t()} | {:error, t(), :not_current}
  def drop(%__MODULE__{current: %{instance_id: instance_id}} = port, instance_id),
    do: {:ok, clear_files(%{port | current: nil})}

  def drop(%__MODULE__{} = port, _instance_id), do: {:error, port, :not_current}

  @doc "Whether the current instance has run its migrations, as the spawn that made it did."
  @spec migrated?(t()) :: boolean()
  def migrated?(%__MODULE__{current: nil}), do: false
  def migrated?(%__MODULE__{current: current}), do: current.migrated

  @doc "Whether `username` is an account of the current instance."
  @spec account?(t(), String.t()) :: boolean()
  def account?(%__MODULE__{current: nil}, _username), do: false

  def account?(%__MODULE__{current: current}, username),
    do: Map.has_key?(current.accounts, username)

  @doc "Whether the password opens an account of the current instance, which records a browser session."
  @spec login(t(), String.t(), String.t()) :: {:ok, t()} | :error
  def login(%__MODULE__{current: nil}, _username, _password), do: :error

  def login(%__MODULE__{current: current} = port, username, password) do
    case Map.fetch(current.accounts, username) do
      {:ok, %{verifier: verifier}} ->
        if CredentialHasher.verify(password, verifier),
          do: {:ok, put_current(port, %{sessions: [username | current.sessions]})},
          else: :error

      :error ->
        :error
    end
  end

  @doc "What the current instance's database holds: its records (accounts, sessions, user records) and chat messages."
  @spec database_contents(t()) :: %{records: non_neg_integer(), chat_messages: non_neg_integer()}
  def database_contents(%__MODULE__{current: nil}), do: %{records: 0, chat_messages: 0}

  def database_contents(%__MODULE__{current: current}) do
    %{
      records: map_size(current.accounts) + length(current.sessions) + length(current.records),
      chat_messages: length(current.messages)
    }
  end

  @doc "Whether the first-admin setup is open: a flat-primary instance with no admin account yet."
  @spec setup_open?(t()) :: boolean()
  def setup_open?(%__MODULE__{current: %{phase: :flat_primary, accounts: accounts}}),
    do: not Enum.any?(accounts, fn {_name, account} -> "admin" in account.roles end)

  def setup_open?(%__MODULE__{}), do: false

  @doc "Every path the port holds for the instance: its directories, pointer and backup configuration."
  @spec leftovers(t()) :: [String.t()]
  def leftovers(%__MODULE__{} = port),
    do: port.directories ++ Enum.reject([port.pointer, port.backup_config], &is_nil/1)

  @doc "The database files the port still holds for the instance. A drop clears them all."
  @spec database_files(t()) :: [String.t()]
  def database_files(%__MODULE__{database_files: files}), do: files

  # The steps of a spawn in the switch's order. Each runs on the port the previous one left. A failed
  # step, or the injected failure after a step that succeeded, rolls the port back to where it began.
  defp run_steps(port, paths, opts) do
    steps = [:create, :migrate, :seed]

    Enum.reduce_while(steps, {:ok, port}, fn step, {:ok, acc} ->
      case step_result(step, acc, paths, opts) do
        {:ok, next} -> run_or_inject(step, next, port, opts)
        {:error, reason} -> {:halt, rollback(port, step, reason)}
      end
    end)
    |> finish(paths, opts)
  end

  # The injected failure fires after the step's work, so the rollback has real work to undo.
  defp run_or_inject(step, next, before, opts) do
    if opts[:fail_after] == step,
      do: {:halt, rollback(before, step, {:injected, step})},
      else: {:cont, {:ok, next}}
  end

  defp step_result(:create, port, paths, opts) do
    phase = Keyword.get(opts, :phase, :sqlite_primary)

    current = %{
      instance_id: paths.instance_id,
      generation: paths.generation,
      instance_root: paths.sqlite_instance_root,
      phase: phase,
      migrated: false,
      accounts: %{},
      sessions: [],
      messages: [],
      records: []
    }

    directories = [paths.sqlite_instance_root] ++ flat_directories(phase, paths)

    {:ok,
     %{
       port
       | current: current,
         directories: directories,
         pointer: paths.storage_pointer_path,
         backup_config: paths.backup_config_path,
         database_files: []
     }}
  end

  defp step_result(:migrate, port, paths, _opts),
    do: {:ok, port |> put_current(%{migrated: true}) |> Map.put(:database_files, [paths.db_file])}

  defp step_result(:seed, port, _paths, opts) do
    case Keyword.get(opts, :seed) do
      nil -> {:ok, port}
      seed -> seed_port(port, seed, opts[:instance_id])
    end
  end

  defp seed_port(port, seed, instance_id) do
    case Seed.validate(seed, %{instance_id: instance_id}) do
      {:ok, normalized} ->
        with {:ok, accounts} <- hash_accounts(normalized["accounts"]) do
          {:ok,
           put_current(port, %{
             accounts: accounts,
             messages: normalized["familyChat"]["messages"],
             records: normalized["records"]
           })}
        end

      {:error, %{reason: reason, path: path}} ->
        {:error, %{invalid: %{reason: reason, path: path}}}
    end
  end

  defp hash_accounts(accounts) do
    accounts
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}}, fn {account, index}, {:ok, done} ->
      {:ok, verifier} = CredentialHasher.hash(account["password"])

      entry = %{user_id: "user-#{index}", roles: account["roles"], verifier: verifier}
      {:cont, {:ok, Map.put(done, account["username"], entry)}}
    end)
  end

  defp finish({:ok, port}, paths, opts) do
    observation = %{
      instance_id: paths.instance_id,
      generation: paths.generation,
      phase: Keyword.get(opts, :phase, :sqlite_primary),
      accounts: account_names(port),
      migrated: port.current.migrated
    }

    {:ok, port, observation}
  end

  defp finish({:error, port, refusal}, _paths, _opts), do: {:error, port, refusal}

  # A refused or failed spawn hands back the port it started from, so nothing it made survives.
  defp rollback(before, step, reason) do
    refusal =
      case reason do
        {:injected, _step} -> %{step: step, reason: :injected}
        %{invalid: invalid} -> %{step: step, invalid: invalid}
        other -> %{step: step, reason: other}
      end

    {:error, before, refusal}
  end

  defp account_names(%{current: current}), do: Enum.sort(Map.keys(current.accounts))

  defp flat_directories(:flat_primary, paths), do: [paths.flat_instance_root]
  defp flat_directories(_phase, _paths), do: []

  defp put_current(%{current: current} = port, changes),
    do: %{port | current: Map.merge(current, changes)}

  defp clear_files(port),
    do: %{port | directories: [], pointer: nil, backup_config: nil, database_files: []}
end
