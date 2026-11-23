defmodule BnestApp.Behaviour.DevelopmentCommandsTest do
  @moduledoc """
  Unit tests for the `development_commands.feature` model and adapter. Every
  scenario of the feature carries a `@scenario` reference below, so the
  behaviour coverage check sees the unit binding the review requires.
  """

  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.DevelopmentCommands.UnitAdapter, as: Adapter
  alias BnestApp.Behaviour.DevelopmentCommandsModel, as: Model

  defp context, do: Adapter.install(%{})

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: Each server keeps to its own loopback port range
  test "port ranges stay inside their allocation on loopback" do
    for {server, first, last, port} <- [
          {"development", 4020, 4029, 4020},
          {"production blue", 4000, 4000, 4000},
          {"production green", 4001, 4001, 4001},
          {"Caddy", 4100, 4100, 4100},
          {"front-end E2E", 4010, 4019, 4010},
          {"back-end E2E", 4030, 4039, 4030}
        ] do
      context()
      |> Adapter.allocate_server(server, first, last)
      |> Adapter.configured_port(server, port)
      |> Adapter.assert_port_binding()
    end

    assert_raise RuntimeError, fn ->
      context()
      |> Adapter.allocate_server("development", 4020, 4029)
      |> Adapter.configured_port("development", 4030)
      |> Adapter.assert_port_binding()
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: npm start serves the development app on its loopback port
  test "the start command leases its own port for the development owner" do
    for {dev_port, port} <- [{nil, 4020}, {"4025", 4025}] do
      lease =
        context()
        |> Adapter.dev_port(dev_port || "(unset)")
        |> Adapter.render_start()
        |> Adapter.assert_lease(port, 4020, 4029)
        |> Adapter.assert_endpoint(port, Model.server_range("development").bind)

      assert lease.commands.endpoint_port == port
    end

    assert {:ok, parsed} =
             "PORT=4025 ./hippo run --class service --lease-port 4025 --lease-owner development --lease-min 4020 --lease-max 4029"
             |> Model.parse_hippo_lease()

    assert parsed == %{
             class: "service",
             lease_port: 4025,
             owner: "development",
             min: 4020,
             max: 4029,
             port: 4025
           }

    assert :error = Model.parse_hippo_lease("no lease here")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: Each npm test command runs its Nx target under a HIPPO admission
  test "test chains run in order and stop after a failure" do
    assert Model.run_chain("be-e2e then fe-e2e", "be-e2e") == {["be-e2e"], ["fe-e2e"]}
    assert Model.run_chain("test:unit", "test:unit") == {["test:unit"], []}

    context()
    |> Adapter.test_chain("test:e2e", "be-e2e then fe-e2e")
    |> Adapter.run_chain_with("be-e2e")
    |> Adapter.assert_chain()
    |> Adapter.assert_admission("test:e2e", "delegates to test:e2e:be and test:e2e:fe")

    assert :ok = Model.check_admission("ephemeral heavy disk .")
    assert {:error, _} = Model.check_admission("ephemeral disk .")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: The tailnet commands drive Tailscale Serve for the Caddy port
  test "tailnet commands drive Tailscale Serve for the Caddy port" do
    assert Model.tailnet_command("tailnet:up") =~ "4100"

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

    assert {:error, _} =
             context()
             |> Adapter.declare_tailnet("tailnet:up", "tailscale serve status")
             |> run_tailnet_safely()
  end

  defp run_tailnet_safely(context) do
    Adapter.run_tailnet(context)
  rescue
    error -> {:error, Exception.message(error)}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/development_commands.feature: Each Nx target runs the checks it names, in order
  test "Nx targets run their declared commands in order" do
    commands = "mix format --check-formatted ;; mix credo --strict"

    context()
    |> Adapter.declare_target("lint", commands, "(none)", "false")
    |> Adapter.read_target()
    |> Adapter.assert_order()

    assert Model.split_commands(commands) == [
             "mix format --check-formatted",
             "mix credo --strict"
           ]

    assert {:error, _} = Model.check_target_shape("lint", "", "(none)", "false")
  end
end
