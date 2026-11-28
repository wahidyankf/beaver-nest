defmodule BnestApp.Behaviour.ProxyModel do
  @moduledoc """
  Pure model of the BN-CLI-05 proxy command surface for
  `specs/apps/bnest/app-be/behaviours/release_and_deploy.feature`.

  Both behaviour layers execute the proxy scenarios through this model. The
  unit adapter feeds it the scenario's own data, which proves the scenario
  logic; the integration adapter feeds it values read back from the real
  deployment tool runs below. The Node suites prove the same contracts
  against the real tool: `assets/test/unit/proxy_commands.test.ts` drives
  the commands behind doubles, and `test:integration` runs the real
  `proxy:status` command in a temporary deploy root.
  """

  @upstream_ports %{"blue" => 4000, "green" => 4001}

  @doc "The loopback port Caddy is managed on."
  def proxy_port, do: 4100

  @doc "The upstream slot port the Caddyfile routes."
  def upstream_port(slot), do: Map.fetch!(@upstream_ports, slot)

  @doc "The line proxy:install prints for the active slot."
  def managed_line(slot), do: "Caddy is managed at 127.0.0.1:#{proxy_port()} for #{slot}."

  @doc "The install sequence proxy:install performs for the active slot."
  def install_plan(slot) do
    %{
      service_calls: ["ensure-caddy", "install-caddy-service"],
      run_heads: [["fmt", "--overwrite"], ["validate", "--config"]],
      upstream: "reverse_proxy 127.0.0.1:#{upstream_port(slot)}",
      printed: managed_line(slot)
    }
  end

  @doc "The exit status proxy:status takes for the probed Caddy."
  def status_exit(true), do: 0
  def status_exit(false), do: 1
end
