defmodule BnestApp.Behaviour.ProxyStatusIntegrationTest do
  @moduledoc """
  Integration test for the `proxy:status` scenario in
  `release_and_deploy.feature`. It runs the real `node
  tools/deployment.mjs proxy:status` command in a temporary deploy root with
  no Caddy listener on the loopback proxy port, so the command takes its
  genuine not-ready path: it prints the routed slot and revision as JSON and
  exits 1.
  """

  use ExUnit.Case, async: true

  @revision "0123456789abcdef0123456789abcdef01234567"
  @previous "fedcba9876543210fedcba9876543210fedcba98"

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/release_and_deploy.feature: proxy:status prints the routed slot and revision and exits 1 when Caddy is not ready
  test "prints the routed slot and revision and exits 1 when Caddy is not ready" do
    assert System.find_executable("node"),
           "node is required on PATH to run tools/deployment.mjs"

    deploy_root =
      Path.join(
        System.tmp_dir!(),
        "bnest-proxy-status-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(deploy_root)

    try do
      File.write!(
        Path.join(deploy_root, "state.json"),
        ~s({"activeSlot":"green","activeRevision":"#{@revision}","previousSlot":"blue","previousRevision":"#{@previous}"})
      )

      {output, status} =
        System.cmd("node", ["tools/deployment.mjs", "proxy:status"],
          env: [{"BNEST_DEPLOY_ROOT", deploy_root}]
        )

      assert status == 1
      assert output =~ ~s("activeSlot": "green")
      assert output =~ ~s("activeRevision": "#{@revision}")
      assert output =~ ~s("previousSlot": "blue")
      assert output =~ ~s("caddyReady": false)
    after
      File.rm_rf!(deploy_root)
    end
  end
end
