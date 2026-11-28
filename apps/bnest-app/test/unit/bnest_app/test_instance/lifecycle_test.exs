defmodule BnestApp.TestInstance.LifecycleTest do
  # Unit proof of the test-isolation lifecycle at the in-memory port: consecutive spawns are
  # disjoint, a spawn finishes its migration and seed before it is current, and teardown and
  # failed spawns leave nothing behind. The port runs the production spawn order and the
  # production seed and path rules, so these rows prove the model's contract; the integration
  # adapter runs the same steps on real files and a real repository.
  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.TestIsolation.Fixtures
  alias BnestApp.Test.InMemory.TestInstancePort
  alias BnestApp.TestInstance.Seed

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/test_isolation.feature: Consecutive tests never share a database
  test "consecutive spawns get disjoint databases" do
    first_id = Fixtures.new_instance_id()
    first_seed = Fixtures.accounts_seed(first_id, ["parent"])
    assert {:ok, _normalized} = Seed.validate(first_seed, %{instance_id: first_id})

    assert {:ok, first_port, first_obs} =
             TestInstancePort.spawn(TestInstancePort.new(),
               instance_id: first_id,
               phase: :sqlite_primary,
               seed: first_seed
             )

    [username] = Fixtures.seeded_usernames(first_seed)
    assert TestInstancePort.account?(first_port, username)
    first_current = TestInstancePort.current(first_port)
    assert first_current.instance_id == first_id
    assert first_obs.generation == first_current.generation

    second_id = Fixtures.new_instance_id()
    assert second_id != first_id

    {:ok, dropped} = TestInstancePort.drop(first_port, first_id)
    assert TestInstancePort.current(dropped) == nil

    assert {:ok, second_port, _second_obs} =
             TestInstancePort.spawn(dropped,
               instance_id: second_id,
               phase: :sqlite_primary
             )

    second_current = TestInstancePort.current(second_port)
    assert second_current.instance_id == second_id
    assert second_current.instance_id != first_current.instance_id
    assert second_current.generation != first_current.generation
    refute TestInstancePort.account?(second_port, username)
    assert TestInstancePort.current(second_port).generation == second_current.generation
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/test_isolation.feature: The spawn returns after its migrations and seed, and the instance stays current until deletion
  test "the spawn finishes its migration and seed before it is current" do
    instance_id = Fixtures.new_instance_id()
    seed = Fixtures.accounts_seed(instance_id, ["admin"])
    assert {:ok, _normalized} = Seed.validate(seed, %{instance_id: instance_id})

    assert {:ok, port, observation} =
             TestInstancePort.spawn(TestInstancePort.new(),
               instance_id: instance_id,
               phase: :sqlite_primary,
               seed: seed
             )

    assert TestInstancePort.migrated?(port)
    assert observation.migrated
    [username] = Fixtures.seeded_usernames(seed)
    assert TestInstancePort.account?(port, username)
    assert {:ok, _port} = TestInstancePort.login(port, username, Fixtures.password())
    assert TestInstancePort.current(port).instance_id == instance_id

    assert {:ok, dropped} = TestInstancePort.drop(port, instance_id)
    assert TestInstancePort.current(dropped) == nil
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/test_isolation.feature: Teardown removes the instance from the running server
  test "teardown clears the current instance and refuses a second delete" do
    instance_id = Fixtures.new_instance_id()

    assert {:ok, port, _observation} =
             TestInstancePort.spawn(TestInstancePort.new(),
               instance_id: instance_id,
               phase: :sqlite_primary
             )

    assert %{instance_id: ^instance_id} = TestInstancePort.current(port)

    assert {:ok, dropped} = TestInstancePort.drop(port, instance_id)
    assert TestInstancePort.current(dropped) == nil
    assert {:error, _port, :not_current} = TestInstancePort.drop(dropped, instance_id)
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/test_isolation.feature: Teardown removes every directory, pointer, and backup configuration the instance made
  test "teardown removes every directory, pointer and database file the instance made" do
    instance_id = Fixtures.new_instance_id()

    assert {:ok, port, _observation} =
             TestInstancePort.spawn(TestInstancePort.new(),
               instance_id: instance_id,
               phase: :sqlite_primary
             )

    assert TestInstancePort.leftovers(port) != []
    assert TestInstancePort.database_files(port) != []

    assert {:ok, dropped} = TestInstancePort.drop(port, instance_id)
    assert TestInstancePort.leftovers(dropped) == []
    assert TestInstancePort.database_files(dropped) == []
    assert TestInstancePort.current(dropped) == nil
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/test_isolation.feature: A failed spawn leaves nothing behind
  test "a spawn that fails at migrate or seed leaves nothing behind" do
    for fail_after <- [:migrate, :seed] do
      instance_id = Fixtures.new_instance_id()
      seed = Fixtures.accounts_seed(instance_id, ["admin", "parent"])
      assert {:ok, _normalized} = Seed.validate(seed, %{instance_id: instance_id})

      before = TestInstancePort.new()

      assert {:error, rolled_back, refusal} =
               TestInstancePort.spawn(before,
                 instance_id: instance_id,
                 phase: :sqlite_primary,
                 seed: seed,
                 fail_after: fail_after
               )

      assert refusal.step == fail_after
      assert TestInstancePort.current(rolled_back) == nil
      assert TestInstancePort.leftovers(rolled_back) == []
      assert TestInstancePort.database_files(rolled_back) == []
    end
  end
end
