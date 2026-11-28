defmodule BnestApp.Behaviour.Proxy.UnitAdapter do
  @moduledoc """
  Unit adapter for the BN-CLI-05 proxy scenarios in
  `specs/apps/bnest/app-be/behaviours/release_and_deploy.feature`.

  It drives the pure proxy model with the scenario's own data, proving the
  scenario logic without touching the host: no file, process, or socket is
  used. The real commands are proven by the Node suites named in the
  model.
  """

  alias BnestApp.Behaviour.ProxyModel, as: Model

  @revision "0123456789abcdef0123456789abcdef01234567"

  def install(context), do: put_proxy(context, %{})

  def release(context), do: context

  defp put_proxy(context, patch) do
    proxy = Map.get(context, :proxy, %{})
    Map.put(context, :proxy, Map.merge(proxy, patch))
  end

  # proxy:install writes a validated Caddy configuration for the active slot
  # and installs its service.

  def route_slot(context, slot), do: put_proxy(context, %{slot: slot})

  def run_install(context) do
    put_proxy(context, %{install_plan: Model.install_plan(context.proxy.slot)})
  end

  def assert_install(context) do
    plan = context.proxy.install_plan
    port = Model.upstream_port(context.proxy.slot)

    unless plan.service_calls == ["ensure-caddy", "install-caddy-service"] do
      raise(
        "proxy:install recorded #{inspect(plan.service_calls)}, " <>
          "expected the Caddy service calls"
      )
    end

    unless plan.run_heads == [["fmt", "--overwrite"], ["validate", "--config"]] do
      raise(
        "proxy:install recorded #{inspect(plan.run_heads)}, " <>
          "expected the Caddy validation calls"
      )
    end

    unless plan.upstream =~ "reverse_proxy" and plan.upstream =~ Integer.to_string(port) do
      raise("proxy:install wrote #{inspect(plan.upstream)}, " <> "expected the routed upstream")
    end

    context
  end

  def assert_line(context, line) do
    expected = Model.managed_line(context.proxy.slot)

    unless line == expected do
      raise("proxy:install printed #{inspect(line)}, expected #{inspect(expected)}")
    end

    context
  end

  # proxy:status prints the routed slot and revision and exits 1 when Caddy
  # is not ready.

  def route_slot_at_revision(context, slot) do
    put_proxy(context, %{slot: slot, revision: @revision, caddy_ready: false})
  end

  def run_status(context) do
    put_proxy(context, %{exit_status: Model.status_exit(context.proxy.caddy_ready)})
  end

  def assert_status(context) do
    proxy = context.proxy

    unless proxy.exit_status == Model.status_exit(false) do
      raise("proxy:status exited #{inspect(proxy.exit_status)}, expected 1")
    end

    unless proxy.revision == @revision do
      raise("proxy:status reported #{inspect(proxy.revision)}, expected the revision")
    end

    context
  end
end
