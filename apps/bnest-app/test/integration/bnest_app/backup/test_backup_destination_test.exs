defmodule BnestApp.TestBackupDestinationTest do
  # Runs real git and changes the VM's environment, so it is an integration test that cannot run beside others.
  use BnestAppWeb.ConnCase, async: false

  alias BnestApp.TestBackupDestination

  @git_variables ~w(GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE)

  # A pre-push hook exports git's repository variables. The helper must still create its own repository,
  # and leave the hook's repository alone.
  test "creates its own repository when git's repository variables point at another one" do
    %{directory: outer} = TestBackupDestination.create!("hook-outer")
    ExUnit.Callbacks.on_exit(fn -> TestBackupDestination.cleanup!(%{directory: outer}) end)

    {_output, 0} =
      System.cmd("git", ["init", "--quiet", outer], env: TestBackupDestination.git_child_env())

    entries_before = outer |> File.ls!() |> Enum.sort()
    config_before = File.read!(Path.join([outer, ".git", "config"]))

    previous = Map.new(@git_variables, &{&1, System.get_env(&1)})
    ExUnit.Callbacks.on_exit(fn -> restore_environment(previous) end)
    System.put_env("GIT_DIR", Path.join(outer, ".git"))
    System.put_env("GIT_WORK_TREE", outer)
    System.put_env("GIT_INDEX_FILE", Path.join([outer, ".git", "index"]))

    default_destination = TestBackupDestination.default_repository!("hook-repository")
    repository = default_destination |> Path.dirname() |> Path.dirname()

    assert File.dir?(Path.join(repository, ".git"))
    assert outer |> File.ls!() |> Enum.sort() == entries_before
    assert File.read!(Path.join([outer, ".git", "config"])) == config_before
    refute File.exists?(Path.join(outer, ".gitignore"))
  end

  defp restore_environment(previous) do
    for {name, value} <- previous do
      if value, do: System.put_env(name, value), else: System.delete_env(name)
    end

    :ok
  end
end
