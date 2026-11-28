defmodule BnestApp.Test.CaddyConfigurationProbe do
  @moduledoc """
  Runs the deployment tool's own Caddy configuration generator, `tools/caddy-config.mjs`, under Node. It returns the
  configuration the generator writes for each slot, with and without a health check. Nothing is written to disk and no
  Caddy process runs.
  """

  @tool_path Path.expand("../../../tools/caddy-config.mjs", __DIR__)

  @script ~S"""
  import { pathToFileURL } from "node:url";
  const { caddyfile, slots } = await import(pathToFileURL(process.argv[1]).href);
  const configs = {};
  for (const slot of Object.keys(slots)) {
    configs[slot] = { healthChecked: caddyfile(slot, true), unchecked: caddyfile(slot, false) };
  }
  console.log(JSON.stringify({ ports: slots, configs }));
  """

  @doc "The configuration the generator writes for each slot, decoded from its Node output."
  def generate do
    node =
      System.find_executable("node") ||
        raise "node is required on PATH to run tools/caddy-config.mjs"

    {output, 0} = System.cmd(node, ["--input-type=module", "-e", @script, @tool_path])
    Jason.decode!(output)
  end

  @doc "No configuration the generator writes names a stream-close delay."
  def omits_stream_close_delay?(probe) do
    Enum.all?(texts(probe), &(not Regex.match?(~r/stream[_-]?close/i, &1)))
  end

  @doc "Every configuration keeps the global five-minute grace period."
  def grace_period_present?(probe) do
    Enum.all?(texts(probe), &Regex.match?(~r/^\tgrace_period 5m$/m, &1))
  end

  @doc "Each slot's configuration routes handshakes to that slot's port and to no other."
  def routed_only_to_own_slot?(probe) do
    Enum.all?(probe["ports"], fn {slot, port} ->
      upstreams(probe, slot) == ["127.0.0.1:#{port}"]
    end)
  end

  @doc "No slot's configuration routes to another slot's port."
  def prior_slot_unrouted?(probe) do
    Enum.all?(probe["ports"], fn {slot, _port} ->
      Enum.all?(probe["ports"], fn {other, other_port} ->
        other == slot or "127.0.0.1:#{other_port}" not in upstreams(probe, slot)
      end)
    end)
  end

  defp upstreams(probe, slot) do
    ~r/reverse_proxy\s+(\S+)/
    |> Regex.scan(probe["configs"][slot]["healthChecked"])
    |> Enum.map(fn [_match, upstream] -> upstream end)
  end

  defp texts(probe) do
    Enum.flat_map(probe["configs"], fn {_slot, config} ->
      [config["healthChecked"], config["unchecked"]]
    end)
  end
end
