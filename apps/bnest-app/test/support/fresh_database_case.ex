defmodule BnestApp.FreshDatabaseCase do
  @moduledoc """
  The ExUnit case template for an integration test that touches the database (ADR 001, sections 1 and 3).

  Its setup spawns one test instance through `BnestApp.TestInstance.spawn!/2`: a new SQLite database, migrated
  by the production entry points, which the running server serves for the length of the test. Its teardown,
  registered with `on_exit/1`, drops whatever instance is current. A teardown that cannot remove it raises, so
  the test that owned it fails and the retained path appears in the message.

  The setup context may set these options, through `@moduletag` or `@tag`:

    * `phase`: `:sqlite_primary` (the default, which production runs) or `:flat_primary` for a scenario that
      tests flat files or the first-admin setup, which then stays open.
    * `instance_id`: a fixed 16-character id. Without it the id is random. A seed whose usernames carry the
      short id needs a fixed one.
    * `seed`: `{seed_key, seed_map}`, applied after migration with the production seed facades.

  The setup returns `instance` and `accounts`, the usernames the seed created in seed order (empty without a
  seed). A case is serial: `TestInstance` holds one instance at a time, so `async: true` is refused.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  use ExUnit.CaseTemplate

  alias BnestApp.TestInstance

  setup context do
    if context[:async] do
      raise ArgumentError,
            "a fresh-database test must be async: false, because TestInstance holds one instance at a time"
    end

    instance = TestInstance.spawn!(TestInstance.application_run!(), spawn_opts(context))
    on_exit(&drop_current/0)

    {seed_key, _seed} = seed_of(context)
    {:ok, instance: instance, accounts: accounts(instance, seed_key)}
  end

  @doc """
  Drops the current test instance, if one is current, and returns `:ok`. A teardown that cannot remove the
  instance raises `BnestApp.TestInstance.Error`, so the failure is never silent. Used by the case's `on_exit`
  and by the ExBdd fresh-database hooks.
  """
  @spec drop_current() :: :ok
  def drop_current do
    case TestInstance.state() do
      nil -> :ok
      instance -> TestInstance.drop!(instance)
    end
  end

  defp spawn_opts(context) do
    [phase: Map.get(context, :phase, :sqlite_primary), label: "fresh-database-case"]
    |> put_instance_id(Map.get(context, :instance_id))
    |> put_seed(seed_of(context))
  end

  defp put_instance_id(opts, nil), do: opts
  defp put_instance_id(opts, instance_id), do: Keyword.put(opts, :instance_id, instance_id)

  defp put_seed(opts, {_seed_key, nil}), do: opts
  defp put_seed(opts, seed), do: Keyword.put(opts, :seed, seed)

  defp seed_of(context), do: Map.get(context, :seed) || {nil, nil}

  defp accounts(_instance, nil), do: []

  defp accounts(instance, seed_key) do
    {:ok, registry} = TestInstance.seed_registry(instance)

    registry
    |> Map.get(:keys, %{})
    |> Map.get(seed_key, %{})
    |> Map.get(:accounts, [])
    |> Enum.map(& &1.username)
  end
end
