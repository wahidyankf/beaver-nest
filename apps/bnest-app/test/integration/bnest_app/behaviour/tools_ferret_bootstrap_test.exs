defmodule BnestApp.Behaviour.ToolsFerretBootstrapIntegrationTest do
  @moduledoc """
  Integration bindings for `ferret-bootstrap.feature`. Each test executes the
  real owning harness `.github/scripts/test-ferret-bootstrap.sh`, which runs
  the pinned `./ferret` wrapper against hermetic fixtures with no network.
  The harness is the proof; this file is the integration-level reference the
  coverage check requires. It runs in the already-wired
  bnest-app:test:integration suite, so no registry or workflow change is
  needed.
  """

  use ExUnit.Case, async: false

  defp run_harness do
    root = Path.expand("../..", File.cwd!())
    script = Path.join(root, ".github/scripts/test-ferret-bootstrap.sh")

    System.cmd(script, [], cd: root, stderr_to_stdout: true)
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/ferret-bootstrap.feature: ./ferret installs and verifies the pinned FERRET before running it
  test "harness installs and verifies the pinned FERRET" do
    {output, status} = run_harness()
    assert status == 0
    assert output =~ "./ferret installs and verifies the pinned FERRET before running it"
    assert output =~ "ferret bootstrap tests passed"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/ferret-bootstrap.feature: ./ferret refuses an unpinned fallback or a failed install
  test "harness refuses fallback and failed installs" do
    {output, status} = run_harness()
    assert status == 0
    assert output =~ "./ferret refuses an unpinned fallback or a failed install"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/ferret-bootstrap.feature: A missing, duplicated, or malformed pin makes ./ferret refuse with 125
  test "harness refuses bad pins with 125" do
    {output, status} = run_harness()
    assert status == 0
    assert output =~ "A missing, duplicated, or malformed pin makes ./ferret refuse with 125"
  end
end
