defmodule BnestApp.Behaviour.Proxy.IntegrationAdapter do
  @moduledoc """
  Integration adapter for the BN-CLI-05 proxy scenarios in
  `specs/apps/bnest/app-be/behaviours/release_and_deploy.feature`.

  It runs the real Node deployment tool in a temporary deploy root.
  `proxy:status` runs as the real command with no Caddy listener, so it
  takes its genuine not-ready path. `proxy:install` would install a system
  service, so it runs the real `installProxy` code behind stub doubles for
  the service manager and the Caddy invocations through a small Node
  driver, writing a real Caddyfile into the temporary deploy root.
  Temporary roots are removed on exit.
  """

  @revision "0123456789abcdef0123456789abcdef01234567"
  @previous "fedcba9876543210fedcba9876543210fedcba98"
  @upstream_ports %{"blue" => 4000, "green" => 4001}

  def install(context), do: put_proxy(context, %{})

  def release(context), do: context

  defp put_proxy(context, patch) do
    proxy = Map.get(context, :proxy, %{})
    Map.put(context, :proxy, Map.merge(proxy, patch))
  end

  defp node! do
    System.find_executable("node") ||
      raise "node is required on PATH to run tools/deployment.mjs"
  end

  defp deployment_tool, do: Path.expand("../../../tools/deployment.mjs", __DIR__)

  defp temporary_deploy_root(prefix) do
    root = Path.join(System.tmp_dir!(), "#{prefix}-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(root)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp route_state(root, slot, revision) do
    File.write!(
      Path.join(root, "state.json"),
      Jason.encode!(%{
        "activeSlot" => slot,
        "activeRevision" => revision,
        "previousSlot" => "blue",
        "previousRevision" => @previous
      })
    )
  end

  # proxy:install writes a validated Caddy configuration for the active slot
  # and installs its service.

  def route_slot(context, slot) do
    root = temporary_deploy_root("bnest-proxy-install")
    route_state(root, slot, @revision)
    put_proxy(context, %{root: root, slot: slot})
  end

  def run_install(context) do
    script = """
    import { readFileSync } from "node:fs";
    import { join } from "node:path";
    import { pathToFileURL } from "node:url";
    const toolPath = process.argv[1];
    const deployRoot = process.argv[2];
    // The tool module runs its CLI when its own path sits in argv[1]; the
    // driver claims that slot so only the doubles-driven command below runs.
    process.argv[1] = "proxy-driver";
    const { createDeploymentTool } = await import(pathToFileURL(toolPath).href);
    const serviceCalls = [];
    const runCalls = [];
    const printed = [];
    const originalWrite = process.stdout.write.bind(process.stdout);
    process.stdout.write = (chunk) => { printed.push(String(chunk)); return true; };
    const tool = createDeploymentTool({
      service: {
        caddyBinary: () => "caddy",
        ensureCaddy: () => { serviceCalls.push("ensure-caddy"); },
        installCaddyService: () => { serviceCalls.push("install-caddy-service"); }
      },
      run: (command, args) => { runCalls.push([command, ...args]); }
    });
    tool.installProxy();
    process.stdout.write = originalWrite;
    const config = readFileSync(join(deployRoot, "caddy", "Caddyfile"), "utf8");
    process.stdout.write(JSON.stringify({ serviceCalls, runCalls, printed: printed.join(""), config }) + "\\n");
    """

    {output, status} =
      System.cmd(
        node!(),
        ["--input-type=module", "-e", script, deployment_tool(), context.proxy.root],
        env: [{"BNEST_DEPLOY_ROOT", context.proxy.root}],
        stderr_to_stdout: true
      )

    if status != 0, do: raise("proxy:install driver failed: #{output}")

    evidence =
      output |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()

    put_proxy(context, %{install: evidence})
  end

  def assert_install(context) do
    install = context.proxy.install
    port = Map.fetch!(@upstream_ports, context.proxy.slot)

    unless install["serviceCalls"] == ["ensure-caddy", "install-caddy-service"] do
      raise(
        "proxy:install recorded #{inspect(install["serviceCalls"])}, expected the Caddy service calls"
      )
    end

    unless Enum.map(install["runCalls"], &hd/1) == ["caddy", "caddy"] do
      raise(
        "proxy:install recorded #{inspect(install["runCalls"])}, expected the Caddy invocations"
      )
    end

    unless install["config"] =~ "reverse_proxy 127.0.0.1:#{port}" do
      raise("proxy:install wrote #{inspect(install["config"])}, expected the routed upstream")
    end

    context
  end

  def assert_line(context, line) do
    unless context.proxy.install["printed"] =~ line do
      raise(
        "proxy:install printed #{inspect(context.proxy.install["printed"])}, expected #{inspect(line)}"
      )
    end

    context
  end

  # proxy:status prints the routed slot and revision and exits 1 when Caddy
  # is not ready.

  def route_slot_at_revision(context, slot) do
    root = temporary_deploy_root("bnest-proxy-status")
    route_state(root, slot, @revision)
    put_proxy(context, %{root: root, slot: slot})
  end

  def run_status(context) do
    {output, status} =
      System.cmd(node!(), ["tools/deployment.mjs", "proxy:status"],
        env: [{"BNEST_DEPLOY_ROOT", context.proxy.root}]
      )

    put_proxy(context, %{status_output: output, exit_status: status})
  end

  def assert_status(context) do
    proxy = context.proxy

    unless proxy.exit_status == 1 do
      raise("proxy:status exited #{inspect(proxy.exit_status)}, expected 1")
    end

    decoded = Jason.decode!(proxy.status_output)

    unless decoded["activeSlot"] == proxy.slot and decoded["activeRevision"] == @revision do
      raise(
        "proxy:status printed #{inspect(proxy.status_output)}, expected the routed slot and revision"
      )
    end

    unless decoded["caddyReady"] == false do
      raise("proxy:status printed #{inspect(proxy.status_output)}, expected caddyReady false")
    end

    context
  end
end
