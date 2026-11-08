defmodule BnestApp.TestInstance.ErrorTest do
  use ExUnit.Case, async: true

  alias BnestApp.TestInstance.Error

  test "names a failed spawn step with its underlying reason" do
    error = %Error{reason: :spawn_failed, step: :migrate, detail: "unknown schedule"}

    assert Exception.message(error) ==
             ~s(test instance spawn failed at migrate: "unknown schedule")
  end

  test "names a cleanup failure with the retained path" do
    error = %Error{reason: :cleanup_failed, path: "/synthetic/run/instances/x", detail: :eacces}

    assert Exception.message(error) ==
             "test instance cleanup failed at /synthetic/run/instances/x: :eacces"
  end

  test "names a refusal, with its detail when it has one" do
    assert Exception.message(%Error{reason: :instance_active}) ==
             "test instance refused: instance_active"

    assert Exception.message(%Error{reason: :refused, detail: :symlink}) ==
             "test instance refused: refused (:symlink)"
  end
end
