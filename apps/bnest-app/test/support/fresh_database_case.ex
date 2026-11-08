defmodule BnestApp.FreshDatabaseCase do
  @moduledoc """
  The ExUnit case template for an integration test that touches the database (ADR 001, sections 1 and 3), and the
  shared spawn-and-seed step that `BnestAppWeb.ConnCase` and the ExBdd fresh-database hooks call.

  Its setup spawns one test instance through `BnestApp.TestInstance.spawn!/2`: a new SQLite database, migrated by
  the production entry points, which the running server serves for the length of the test. Its teardown, registered
  with `on_exit/1`, drops whatever instance is current. A teardown that cannot remove it raises, so the test that
  owned it fails and the retained path appears in the message.

  The context may set these options, through `@moduletag` or `@tag`:

    * `phase`: `:sqlite_primary` (the default, which production runs) or `:flat_primary` for a scenario that
      tests flat files or the first-admin setup, which then stays open.
    * `instance_id`: a fixed 16-character id. Without it the id is random. A seed whose usernames carry the
      short id needs a fixed one.
    * `seed`: `{seed_key, seed_map}`, applied after migration with the production seed facades. It replaces the
      default accounts.

  Without a `seed` option, the default accounts are the ones the case passes (`standard_accounts/0` for
  `ConnCase`). Each username is `test-user-<name>-<short id>`, where the short id is the first eight characters
  of the instance id, so the usernames of two instances never collide.

  The setup returns `instance` and `accounts`, the usernames the seed created in seed order (empty without a
  seed). A case is serial: `TestInstance` holds one instance at a time, so `async: true` is refused.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  use ExUnit.CaseTemplate

  alias BnestApp.TestInstance

  # The key of the default seed. A test that passes its own `seed` option names its own key.
  @default_seed_key "accounts"
  @account_password "Synthetic Integration Password 123!"

  setup context do
    {:ok, fresh_database!(context)}
  end

  @doc "The default accounts every `ConnCase` test is seeded with: the admin and one child account, by name."
  @spec standard_accounts() :: [{String.t(), [String.t()]}]
  def standard_accounts, do: [{"integration", ["admin", "parents"]}, {"other", ["children"]}]

  @doc "The synthetic password of every seeded account."
  @spec account_password() :: String.t()
  def account_password, do: @account_password

  @doc """
  Spawns the test's instance, registers its drop with `on_exit/1`, and returns the setup keyword list
  `[instance: instance, accounts: usernames]`. Refuses an `async` test.
  """
  @spec fresh_database!(map(), [{String.t(), [String.t()]}]) :: keyword()
  def fresh_database!(context, default_accounts \\ []) do
    if context[:async] do
      raise ArgumentError,
            "a fresh-database test must be async: false, because TestInstance holds one instance at a time"
    end

    {instance, accounts} = spawn_for!(context, default_accounts)
    on_exit(&drop_current/0)
    [instance: instance, accounts: accounts]
  end

  @doc """
  Spawns the instance for a test without registering a drop, for a caller that owns the teardown itself (the ExBdd
  before hook, whose after hook calls `drop_current/0`). Returns `{instance, usernames}`.
  """
  @spec spawn_for!(map(), [{String.t(), [String.t()]}]) :: {TestInstance.instance(), [String.t()]}
  def spawn_for!(context, default_accounts \\ []) do
    instance_id = Map.get(context, :instance_id) || random_instance_id()
    {seed_key, seed} = seed_for(context, instance_id, default_accounts)

    opts =
      [
        phase: Map.get(context, :phase, :sqlite_primary),
        label: "fresh-database-case",
        instance_id: instance_id
      ]
      |> put_seed(seed_key, seed)

    instance = TestInstance.spawn!(TestInstance.application_run!(), opts)
    {instance, usernames(seed_key)}
  end

  @doc """
  The accounts that the current instance's seed under `seed_key` created, in seed order. Empty when no instance is
  current or the seed is absent.
  """
  @spec seeded_accounts(String.t()) :: [map()]
  def seeded_accounts(seed_key \\ @default_seed_key) do
    with instance when instance != nil <- TestInstance.state(),
         {:ok, registry} <- TestInstance.seed_registry(instance) do
      registry
      |> Map.get(:keys, %{})
      |> Map.get(seed_key, %{})
      |> Map.get(:accounts, [])
    else
      _none -> []
    end
  end

  @doc "The current instance's default seed accounts, by the name each was given."
  @spec default_account(String.t()) :: map() | nil
  def default_account(name) do
    prefix = "test-user-#{name}-"
    Enum.find(seeded_accounts(), &String.starts_with?(&1.username, prefix))
  end

  @doc """
  Drops the current test instance, if one is current, and returns `:ok`. A teardown that cannot remove the
  instance raises `BnestApp.TestInstance.Error`, so the failure is never silent. Used by the case's `on_exit` and
  by the ExBdd fresh-database hooks.
  """
  @spec drop_current() :: :ok
  def drop_current do
    case TestInstance.state() do
      nil -> :ok
      instance -> TestInstance.drop!(instance)
    end
  end

  # A test's own `seed` option wins. Otherwise the default accounts are built with the short id of the instance
  # the spawn will create, so their usernames carry it.
  defp seed_for(%{seed: {seed_key, seed_map}}, _instance_id, _default), do: {seed_key, seed_map}

  defp seed_for(_context, _instance_id, []), do: {nil, nil}

  defp seed_for(_context, instance_id, default_accounts) do
    short = String.slice(instance_id, 0, 8)

    accounts =
      Enum.map(default_accounts, fn {name, roles} ->
        %{
          "username" => "test-user-#{name}-#{short}",
          "password" => @account_password,
          "roles" => roles
        }
      end)

    {@default_seed_key, %{"accounts" => accounts}}
  end

  defp put_seed(opts, nil, nil), do: opts
  defp put_seed(opts, seed_key, seed), do: Keyword.put(opts, :seed, {seed_key, seed})

  defp usernames(nil), do: []

  defp usernames(seed_key), do: seeded_accounts(seed_key) |> Enum.map(& &1.username)

  defp random_instance_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
