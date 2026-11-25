defmodule BnestApp.Behaviour.ToolsRepositoryGatesRoutingIntegrationTest do
  @moduledoc """
  Integration binding for the pull-request routing scenario in
  `repository_gates.feature`. The test executes the real routing predicate
  `.github/scripts/test-pr-quality-routing.sh`, which proves the conditional
  suite table against isolated Git fixtures. It runs in the already-wired
  bnest-app:test:integration suite, so no registry or workflow change is
  needed.
  """

  use ExUnit.Case, async: false

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The pull-request gate routes the conditional suites by the changed paths
  test "routing predicate passes over isolated fixtures" do
    root = Path.expand("../..", File.cwd!())
    script = Path.join(root, ".github/scripts/test-pr-quality-routing.sh")

    {output, status} = System.cmd(script, [], cd: root, stderr_to_stdout: true)
    assert status == 0
    assert output =~ "PR quality routing: 13 passed, 0 failed"
  end
end
