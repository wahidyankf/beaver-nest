defmodule BnestApp.Behaviour.ScenarioHooksTest do
  # The ExBdd hooks that give every integration scenario its fresh instance (ADR 001, section 1). ExBdd runs no after
  # hook when a before hook or a Background step fails, so the drop must also be registered with ExUnit, or the
  # instance stays current and every later scenario is refused.
  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.IntegrationSupport
  alias BnestApp.FreshDatabaseCase
  alias BnestApp.TestInstance

  @spawn_hook :before_scenario_named_spawn_a_fresh_test_instance_for_the_scenario
  @context %{feature_file: "scenario_hooks.feature", scenario_name: "hook probe"}

  setup do
    assert TestInstance.state() == nil
    :ok
  end

  test "the spawn hook registers the instance drop, so a failing Background step leaks nothing" do
    # Registered first, so it runs last: after ExUnit's own callbacks and without any after hook.
    on_exit(fn ->
      leaked = TestInstance.state()
      FreshDatabaseCase.drop_current()
      assert leaked == nil, "the scenario instance stayed current after the test ended"
    end)

    assert {:ok, _context} = apply(IntegrationSupport, @spawn_hook, [@context])
    assert TestInstance.state() != nil
  end

  test "releasing the instance fails when the scenario left data in the shared run base" do
    {_instance, _accounts} = FreshDatabaseCase.spawn_for!(%{}, [])
    on_exit(&FreshDatabaseCase.drop_current/0)

    run = TestInstance.application_run!()
    leak = Path.join(run.path, "system/accounts/user-scenario-hooks-probe.json")
    File.mkdir_p!(Path.dirname(leak))
    File.write!(leak, "{}")
    on_exit(fn -> File.rm(leak) end)

    error = assert_raise RuntimeError, fn -> IntegrationSupport.release_instance!() end
    assert error.message =~ "user-scenario-hooks-probe.json"
    assert TestInstance.state() == nil
  end
end
