defmodule BnestApp.Test.SlotUnitProbe do
  @moduledoc """
  Runs the deployment tool's own systemd unit generator, `tools/systemd.mjs`, under Node and reads the `RELEASE_DISTRIBUTION`
  each slot's unit sets. The generator writes nothing here: `slotUnit` returns the unit text, and the paths it is given are
  synthetic strings that are never read.
  """

  @tool_path Path.expand("../../../tools/systemd.mjs", __DIR__)

  @script ~S"""
  import { pathToFileURL } from "node:url";
  const tool = await import(pathToFileURL(process.argv[1]).href);
  const { slots } = await import(new URL("./caddy-config.mjs", pathToFileURL(process.argv[1])).href);
  const options = {
    runtimeRoot: "/nonexistent/probe/runtime",
    revision: "probe",
    release: "/nonexistent/probe/release",
    environmentPath: "/nonexistent/probe/environment",
    logPath: "/nonexistent/probe/out.log",
    errorPath: "/nonexistent/probe/err.log",
    productionHost: "probe.invalid",
    webPushPublicKeyFile: "/nonexistent/probe/public",
    webPushPrivateKeyFile: "/nonexistent/probe/private",
    webPushSubject: "mailto:probe@invalid",
  };
  const units = {};
  for (const slot of Object.keys(slots)) units[slot] = tool.slotUnit(slot, options);
  console.log(JSON.stringify(units));
  """

  @doc """
  The `RELEASE_DISTRIBUTION` values each slot's generated unit sets, by slot name. Every slot the generator knows of
  is listed, so a slot whose unit sets no value shows as an empty list.
  """
  def distributions do
    Map.new(generate(), fn {slot, unit} ->
      {slot,
       Regex.scan(~r/RELEASE_DISTRIBUTION=([^"\s]*)/, unit)
       |> Enum.map(fn [_, value] -> value end)}
    end)
  end

  defp generate do
    node =
      System.find_executable("node") ||
        raise "node is required on PATH to run tools/systemd.mjs"

    {output, 0} =
      System.cmd(node, ["--input-type=module", "-e", @script, @tool_path],
        env: [{"BNEST_DEPLOY_ROOT", Path.join(System.tmp_dir!(), "bnest-slot-unit-probe")}]
      )

    Jason.decode!(output)
  end
end
