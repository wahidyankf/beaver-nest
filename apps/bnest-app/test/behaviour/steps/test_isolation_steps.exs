defmodule BnestApp.Behaviour.TestIsolationSteps do
  @moduledoc """
  Bindings for `specs/apps/bnest/app-be/behaviours/test_isolation.feature` (ADR 001, section 6).

  Each step delegates to the adapter the layer's hook installed (`context.isolation_adapter`). The unit
  adapter drives the pure test-side port and the production guard decision; the integration adapter drives
  the real switch, seed facades, SQLite repo and endpoint. A Given or When records what it observed, and a
  Then asserts that recorded evidence, so no step is a placeholder or a success literal.
  """

  use ExBdd.StepDefinition

  import ExUnit.Assertions

  alias BnestApp.Behaviour.TestIsolation.Fixtures

  # Given

  step("no test instance is current", context, do: assert_none_current(context))

  step("a test instance was spawned and migrated", context,
    do: context |> spawn_plain() |> assert_spawned()
  )

  step("a test instance is current", context,
    do: context |> spawn_plain() |> assert_spawned() |> assert_current()
  )

  step("the build environment is production", context,
    do: adapter(context).set_build_environment(context, :prod)
  )

  step("seeding will fail after the first seeded account is created", context,
    do: adapter(context).inject_failure(context, :seed)
  )

  step("the migration will fail on its first migration", context,
    do: adapter(context).inject_failure(context, :migrate)
  )

  # When

  step("a test spawns an instance", context, do: spawn_plain(context))

  step("a test spawns an instance with two seeded accounts", context,
    do: spawn_seeded(context, ["admin", "parent"])
  )

  step("the test deletes the instance", context, do: adapter(context).delete_current(context))

  step("a client on a non-loopback address creates a test instance with the run secret", context,
    do: adapter(context).create_request(context, :non_loopback)
  )

  step(
    "the build is assembled with the testing control flag on",
    context,
    do: adapter(context).decide_mounts(context)
  )

  # Schema steps. The unit layer has no database, so its answers are PARTIAL: it checks the digest's
  # discriminating properties on fixed rows, and the integration layer proves equality with the release
  # database (see the integration adapter and the Fingerprint parity test).
  step(
    "its schema is compared with a database built by the release migration entry points",
    context,
    do: adapter(context).compare_release_schema(context)
  )

  # Then

  # Unit: the digest is order-independent and detects an extra object (PARTIAL, not equality).
  # Integration: the instance's digest equals the release database's digest (exact).
  step("the schema objects and the applied migration versions are identical", context,
    do: assert_schema_identical(context)
  )

  # Unit: the digest detects a missing version (PARTIAL). Integration: both databases hold exactly the
  # committed migration files' versions, in order (exact).
  step("the applied migration versions match the committed migration files exactly", context,
    do: assert_versions_exact(context)
  )

  step(
    "no instance directory, storage pointer, or backup configuration file for that instance remains",
    context,
    do: assert_no_leftovers(context)
  )

  step("the run root holds no database file", context, do: assert_no_instance_database(context))

  step(
    "the response is the stock \"Not Found\" response that a missing route gets",
    context,
    do: assert_stock_response(context)
  )

  step("no test instance is created", context, do: assert_none_current(context))

  step("the build exposes no testing endpoint", context, do: assert_no_mount(context))

  step(
    "no instance directory, storage pointer, or backup configuration file remains",
    context,
    do: assert_no_leftovers(context)
  )

  step("the spawn fails at the seed step", context, do: assert_failed_at(context, :seed))

  step("the spawn fails at the migrate step", context, do: assert_failed_at(context, :migrate))

  # Shared actions. The adapter is the layer's; every assertion is the feature's.

  defp adapter(context), do: context.isolation_adapter

  defp spawn_plain(context, opts \\ []) do
    context = adapter(context).choose_instance_id(context)
    adapter(context).spawn_instance(context, opts)
  end

  defp spawn_seeded(context, kinds) do
    context = adapter(context).choose_instance_id(context)
    seed = Fixtures.accounts_seed(context.isolation.instance_id, kinds)

    adapter(context).spawn_instance(context,
      seed: seed,
      usernames: Fixtures.seeded_usernames(seed)
    )
  end

  # Assertions

  defp assert_none_current(context) do
    assert adapter(context).current(context) == nil
    context
  end

  defp assert_current(context) do
    assert adapter(context).current(context) != nil
    context
  end

  defp assert_spawned(context) do
    assert {:ok, _observed} = context.spawn
    context
  end

  defp assert_schema_identical(context) do
    assert adapter(context).schema_identical?(context)
    context
  end

  defp assert_versions_exact(context) do
    assert adapter(context).versions_exact?(context)
    context
  end

  defp assert_no_leftovers(context) do
    assert adapter(context).leftovers(context) == []
    context
  end

  defp assert_no_instance_database(context) do
    assert adapter(context).instance_database_files(context) == []
    context
  end

  # A refused create answers exactly what a request to a missing route answers.
  defp assert_stock_response(context) do
    assert context.request.response == context.request.missing
    context
  end

  defp assert_no_mount(context) do
    assert context.mount.decision == false
    assert Enum.all?(context.mount.checks, &(&1 == false))
    context
  end

  defp assert_failed_at(context, step) do
    assert {:error, %{step: ^step}} = context.spawn
    context
  end
end
