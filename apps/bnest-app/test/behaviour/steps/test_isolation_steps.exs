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

  # The seeded account must read back in its own instance: a later absence in the next instance then
  # means the account is gone, not that the read could never find it.
  step("a test spawned an instance and created an account in it", context,
    do: context |> spawn_seeded(["admin"]) |> assert_spawned() |> assert_seeded_accounts_present()
  )

  step("a test instance is current", context,
    do: context |> spawn_plain() |> assert_spawned() |> assert_current()
  )

  step("seeding will fail after the first seeded account is created", context,
    do: adapter(context).inject_failure(context, :seed)
  )

  step("the migration will fail on its first migration", context,
    do: adapter(context).inject_failure(context, :migrate)
  )

  # When

  step("a test spawns an instance with no seeded accounts", context,
    do: context |> spawn_plain(phase: :flat_primary)
  )

  step("the next test spawns its own instance", context,
    do:
      context
      |> adapter(context).end_test()
      |> adapter(context).choose_instance_id()
      |> adapter(context).spawn_instance([])
  )

  step("a test spawns an instance with one seeded account", context,
    do: spawn_seeded(context, ["admin"])
  )

  step("a test spawns an instance with two seeded accounts", context,
    do: spawn_seeded(context, ["admin", "parent"])
  )

  step(
    "a test spawns an instance with a seeded account named {string}",
    %{args: [name]} = context,
    do: spawn_named(context, name)
  )

  step("the test deletes the instance", context, do: adapter(context).delete_current(context))

  step("a client creates a test instance without the testing header", context,
    do: adapter(context).create_request(context, :no_header)
  )

  step(
    "a client creates a test instance with a testing header that is not the run secret",
    context,
    do: adapter(context).create_request(context, :wrong_header)
  )

  step(
    "a client creates a test instance with the run secret and an x-forwarded-for header",
    context,
    do: adapter(context).create_request(context, :forwarded)
  )

  step(
    "a client on a non-loopback address creates a test instance with the run secret",
    context,
    do: adapter(context).create_request(context, :non_loopback)
  )

  # Then

  step(
    "no account can log in, the chat has no messages, and the initial setup page is open",
    context,
    do: context |> assert_empty_database() |> assert_setup_open()
  )

  step("the instance database holds no browser session or user record", context,
    do: assert_no_session_or_user_record(context)
  )

  step("the next instance has a different instance ID and generation", context,
    do: assert_new_instance(context)
  )

  step(
    "the account created by the previous test cannot be found in the next instance",
    context,
    do: assert_previous_account_absent(context)
  )

  step("the readiness check reports the generation of the next instance", context,
    do: assert_readiness_reports_next(context)
  )

  step("the spawn returns only after its migrations and its seed have finished", context,
    do: assert_spawn_completed(context)
  )

  step("the seeded account can log in as soon as the spawn returns", context,
    do: assert_login(context)
  )

  step("the instance stays current until the test deletes it", context,
    do: assert_current(context)
  )

  step("the server reports no current instance", context, do: assert_server_reports_none(context))

  step("a second delete of that instance is refused", context,
    do: assert_second_delete_refused(context)
  )

  step(
    "no instance directory, storage pointer, or backup configuration file for that instance remains",
    context,
    do: assert_no_leftovers(context)
  )

  step("the run root holds no database file", context, do: assert_no_run_base_database(context))

  step(
    "the response is the stock \"Not Found\" response that a missing route gets",
    context,
    do: assert_stock_response(context)
  )

  step("no test instance is created", context, do: assert_none_current(context))

  step("the spawn response lists exactly those two accounts", context,
    do: assert_lists_sent_accounts(context)
  )

  step("each listed username starts with {string}", %{args: [prefix]} = context,
    do: assert_usernames_start_with(context, prefix)
  )

  step(
    "each listed username carries the first eight characters of the instance ID",
    context,
    do: assert_usernames_carry_short_id(context)
  )

  step(
    "the spawn is refused with an invalid username error that names the username field",
    context,
    do: assert_refused_for_username(context)
  )

  step("no instance directory remains for that spawn", context,
    do: assert_no_instance_directory(context)
  )

  step("the spawn fails at the seed step", context, do: assert_failed_at(context, :seed))

  step("the spawn fails at the migrate step", context, do: assert_failed_at(context, :migrate))

  step(
    "no instance directory, storage pointer, or backup configuration file remains",
    context,
    do: assert_no_leftovers(context)
  )

  # Seeding after a spawn, and the conflicting testing-control answers. Each answer is the status and the
  # body the route gave, so the assertion reads what a client receives.

  step("a test seeded a current instance under a seed key", context,
    do: adapter(context).prepare_seeded(context)
  )

  step("a scheduler task is running", context, do: adapter(context).hold_scheduler_task(context))

  step("a test seeds the current instance under a new seed key", context,
    do: adapter(context).seed_request(context, :new_key)
  )

  step("the test repeats that seed key with the same body", context,
    do: adapter(context).seed_request(context, :same_body)
  )

  step("a test seeds the current instance with another body under it", context,
    do: adapter(context).seed_request(context, :other_body)
  )

  step("a test seeds an instance that is not current", context,
    do: adapter(context).seed_request(context, :not_current)
  )

  step("a test asks the server to spawn an instance under another run id", context,
    do: adapter(context).spawn_request(context, :other_run)
  )

  step("a test asks the server to spawn an instance", context,
    do: adapter(context).spawn_request(context, :plain)
  )

  step("the seed answers applied true and the seeded account can log in", context,
    do: context |> assert_applied(true) |> assert_seed_account_logs_in()
  )

  step("the repeat answers applied false and writes no new account", context,
    do: context |> assert_applied(false) |> assert_one_seed_account()
  )

  step("the response is a 409 answer with the code {string}", %{args: [code]} = context,
    do: assert_conflict(context, code)
  )

  step("the answer echoes none of the request's input", context, do: assert_no_echo(context))

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

  defp spawn_named(context, name) do
    context = adapter(context).choose_instance_id(context)

    adapter(context).spawn_instance(context,
      seed: Fixtures.named_admin_seed(name),
      usernames: [name]
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

  defp assert_empty_database(context) do
    contents = adapter(context).database_contents(context)

    assert contents.records == 0
    assert contents.chat_messages == 0
    context
  end

  # Browser sessions and user records are both records the unit port counts in `records`, and SQLite
  # keeps the instance's records in `bnest_records`, so an empty record count holds neither.
  defp assert_no_session_or_user_record(context) do
    assert adapter(context).database_contents(context).records == 0
    context
  end

  defp assert_setup_open(context) do
    assert adapter(context).setup_open?(context)
    context
  end

  defp assert_new_instance(context) do
    {:ok, next} = context.spawn
    {:ok, previous} = context.previous_spawn

    assert next.instance_id != previous.instance_id
    assert next.generation != previous.generation
    context
  end

  defp assert_previous_account_absent(context) do
    {:ok, previous} = context.previous_spawn
    [username | _rest] = previous.accounts

    refute adapter(context).account_present?(context, username)
    context
  end

  defp assert_readiness_reports_next(context) do
    {:ok, next} = context.spawn

    assert adapter(context).readiness_generation(context) == next.generation
    context
  end

  # Reads through the same `account_present?` reader the absence Then uses, so the control tests that reader.
  defp assert_seeded_accounts_present(context) do
    {:ok, spawned} = context.spawn

    assert spawned.accounts != []

    for username <- spawned.accounts do
      assert adapter(context).account_present?(context, username)
    end

    context
  end

  defp assert_spawn_completed(context) do
    completion = adapter(context).spawn_completion(context)

    assert completion.migrated
    assert Enum.all?(completion.seeded, fn {_username, present?} -> present? end)
    context
  end

  defp assert_login(context) do
    assert adapter(context).login_seeded(context) == :ok
    context
  end

  defp assert_server_reports_none(context) do
    assert adapter(context).server_state(context) == nil
    context
  end

  defp assert_second_delete_refused(context) do
    assert context.delete.first == 204
    assert context.delete.again == {409, "not_current"}
    context
  end

  defp assert_no_leftovers(context) do
    assert adapter(context).leftovers(context) == []
    context
  end

  defp assert_no_run_base_database(context) do
    assert adapter(context).run_base_database_files(context) == []
    context
  end

  # A refused create answers exactly what a request to a missing route answers.
  defp assert_stock_response(context) do
    assert context.request.response == context.request.missing
    context
  end

  defp assert_lists_sent_accounts(context) do
    {:ok, spawned} = context.spawn

    assert Enum.sort(spawned.accounts) == Enum.sort(context.sent_usernames)
    context
  end

  defp assert_usernames_start_with(context, prefix) do
    {:ok, spawned} = context.spawn

    for username <- spawned.accounts do
      assert String.starts_with?(username, prefix)
    end

    context
  end

  defp assert_usernames_carry_short_id(context) do
    {:ok, spawned} = context.spawn
    short = Fixtures.short_id(spawned.instance_id)

    assert spawned.instance_id == context.isolation.instance_id

    for username <- spawned.accounts do
      assert short in String.split(username, "-")
    end

    context
  end

  defp assert_refused_for_username(context) do
    assert {:error, %{step: :seed, invalid: %{reason: :invalid_username, path: path}}} =
             context.spawn

    assert String.ends_with?(path, ".username")
    context
  end

  defp assert_no_instance_directory(context) do
    assert adapter(context).instance_directories(context) == []
    context
  end

  defp assert_failed_at(context, step) do
    assert {:error, %{step: ^step}} = context.spawn
    context
  end

  defp assert_applied(context, applied) do
    assert %{status: 200, body: %{"applied" => ^applied}} = context.isolation_answer
    context
  end

  defp assert_seed_account_logs_in(context) do
    assert adapter(context).seed_account_login(context) == :ok
    context
  end

  # The repeat of a seed writes nothing, so the seed's one account is still the only one it made.
  defp assert_one_seed_account(context) do
    assert adapter(context).seed_account_count(context) == 1
    context
  end

  defp assert_conflict(context, code) do
    answer = context.isolation_answer

    assert match?(%{status: 409, body: %{"error" => %{"code" => ^code}}}, answer),
           "expected a 409 #{code} answer, got #{inspect(answer)}"

    context
  end

  # The answer repeats none of the values the request sent: the run id, the seed key, the instance id.
  defp assert_no_echo(context) do
    %{body: body, sent: sent} = context.isolation_answer
    text = inspect(body)

    Enum.each(sent, fn value -> refute String.contains?(text, value) end)
    context
  end
end
