defmodule BnestApp.Behaviour.ToolsScheduledGatesWorkflowIntegrationTest do
  @moduledoc """
  Integration binding for the scheduled-gates scenario in `repository_gates.feature`. The test reads the real
  scheduled workflow, the front-end end-to-end project config, and `repo-config.yml` as text and runs them through
  `BnestApp.ScheduledGatesWorkflow`, the same pure check the unit binding drives with inline fixtures. A dropped
  matrix project, a job that waits for the other suite, a changed cron or zone, or a leg that points at the wrong
  registry entry fails here with the finding. It runs in the already-wired bnest-app:test:integration suite, which
  the pull-request entry test-integration runs, so no registry or workflow change is needed.
  """

  use ExUnit.Case, async: false

  alias BnestApp.ScheduledGatesWorkflow

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  test "the real scheduled workflow, project config, and registry hold the declared shape" do
    root = Path.expand("../..", File.cwd!())
    read = fn path -> File.read!(Path.join(root, path)) end

    findings =
      ScheduledGatesWorkflow.findings(
        read.(".github/workflows/scheduled-quality-gates.yml"),
        read.("apps/bnest-app-fe-e2e/playwright.config.mts"),
        read.("repo-config.yml")
      )

    assert findings == [],
           "the scheduled gates drifted from the scenario:\n  - " <> Enum.join(findings, "\n  - ")
  end
end
