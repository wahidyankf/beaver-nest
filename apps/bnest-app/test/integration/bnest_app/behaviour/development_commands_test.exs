defmodule BnestApp.Behaviour.DevelopmentCommandsIntegrationTest do
  @moduledoc """
  Integration tests for the `development_commands.feature` adapter. The bound
  scenarios read back the real repository files: the start command comes from
  the real `package.json`, the endpoint configuration from the real config
  files, and the tailnet commands run against a recording double. Exempt
  scenarios need no marker here; their `@integration-exempt` tag is the
  integration proof the review records.
  """

  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.DevelopmentCommands.IntegrationAdapter, as: Adapter

  defp context, do: Adapter.install(%{})

  # @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: npm start serves the development app on its loopback port
  test "the start command leases its port and the endpoint binds loopback" do
    for {dev_port, port} <- [{"(unset)", 4020}, {"4025", 4025}] do
      context()
      |> Adapter.dev_port(dev_port)
      |> Adapter.render_start()
      |> Adapter.assert_lease(port, 4020, 4029)
      |> Adapter.assert_endpoint(port, "127.0.0.1")
    end
  end

  # @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: The tailnet commands drive Tailscale Serve for the Caddy port
  test "tailnet targets run their declared command against a recording double" do
    for {target, command} <- [
          {"tailnet:up", "tailscale serve --bg --yes --https=443 --set-path=/ 4100"},
          {"tailnet:status", "tailscale serve status"},
          {"tailnet:down", "tailscale serve --https=443 --set-path=/ off"}
        ] do
      context()
      |> Adapter.declare_tailnet(target, command)
      |> Adapter.run_tailnet()
      |> Adapter.assert_tailnet(command)
    end
  end
end
