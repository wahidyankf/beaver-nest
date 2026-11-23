defmodule BnestApp.Behaviour.DevelopmentCommandsModel do
  @moduledoc """
  Pure model of the development command surface for
  `specs/apps/bnest/app-be/behaviours/development_commands.feature`.

  Both behaviour layers execute the scenarios through this model. The unit
  adapter feeds it the scenario's own data, which proves the scenario logic;
  the integration adapter feeds it values read back from the real repository
  files, which proves the implementation. The Node suites in
  `apps/bnest-app/tools/release.test.mjs` prove the same contracts against
  the real scripts with recording doubles.
  """

  @servers %{
    "development" => %{first: 4020, last: 4029, bind: "127.0.0.1"},
    "production blue" => %{first: 4000, last: 4000, bind: "127.0.0.1"},
    "production green" => %{first: 4001, last: 4001, bind: "127.0.0.1"},
    "Caddy" => %{first: 4100, last: 4100, bind: "127.0.0.1"},
    "front-end E2E" => %{first: 4010, last: 4019, bind: "127.0.0.1"},
    "back-end E2E" => %{first: 4030, last: 4039, bind: "127.0.0.1"}
  }

  @tailnet %{
    "tailnet:up" => "tailscale serve --bg --yes --https=443 --set-path=/ 4100",
    "tailnet:status" => "tailscale serve status",
    "tailnet:down" => "tailscale serve --https=443 --set-path=/ off"
  }

  @doc "The reviewed loopback allocation for a server, or `:unknown`."
  def server_range(server), do: Map.get(@servers, server, :unknown)

  @doc "The reviewed tailnet command for a target, or `:unknown`."
  def tailnet_command(target), do: Map.get(@tailnet, target, :unknown)

  @doc "True when the port stays inside its allocated range."
  def port_in_range?(first, last, port),
    do:
      is_integer(first) and is_integer(last) and is_integer(port) and first <= port and
        port <= last

  @doc "True when the bind address is the loopback address every server keeps to."
  def loopback?("127.0.0.1"), do: true
  def loopback?(_), do: false

  @doc """
  Renders the start command the way `npm start` builds it: PORT defaults to
  4020 and the HIPPO lease requests the same port for the development owner
  inside 4020 to 4029.
  """
  def render_start(dev_port) do
    port = if dev_port in [nil, ""], do: "4020", else: dev_port

    "BNEST_STABLE=${BNEST_STABLE:-true} PORT=#{port} " <>
      "./hippo run --class service --resource-tier standard --disk-path . " <>
      "--cwd apps/bnest-app --lease-port #{port} --lease-owner development " <>
      "--lease-min 4020 --lease-max 4029 -- mix phx.server"
  end

  @doc "Parses the HIPPO lease out of a rendered start command."
  def parse_hippo_lease(command) do
    with [_, class] <- Regex.run(~r/--class (\S+)/, command),
         [_, lease_port] <- Regex.run(~r/--lease-port (\d+)/, command),
         [_, owner] <- Regex.run(~r/--lease-owner (\S+)/, command),
         [_, min] <- Regex.run(~r/--lease-min (\d+)/, command),
         [_, max] <- Regex.run(~r/--lease-max (\d+)/, command),
         [_, port] <- Regex.run(~r/\bPORT=(\d+)/, command) do
      {:ok,
       %{
         class: class,
         lease_port: String.to_integer(lease_port),
         owner: owner,
         min: String.to_integer(min),
         max: String.to_integer(max),
         port: String.to_integer(port)
       }}
    else
      _ -> :error
    end
  end

  @doc """
  Splits a test chain on `then` and runs it with one target failing: the
  targets up to and including the failure execute, the targets after it never
  run. Mirrors the shell `&&` chaining of `npm run test:e2e`.
  """
  def run_chain(chain, failing) do
    targets = chain |> String.split(~r/\s+then\s+/) |> Enum.map(&String.trim/1)
    {ran, rest} = Enum.split_while(targets, &(&1 != failing))
    ran = if rest == [], do: ran, else: ran ++ [failing]
    skipped = if rest == [], do: [], else: tl(rest)
    {ran, skipped}
  end

  @doc """
  Checks the reviewed admission shape: either three space-separated parts
  (class, tier, disk marker) or a delegation to two other test scripts.
  """
  def check_admission("delegates to " <> rest) do
    if rest =~ ~r/^test:\S+ and test:\S+$/, do: :ok, else: {:error, "not a delegation"}
  end

  def check_admission(admission) do
    case String.split(admission, " ") do
      [class, tier, "disk", "."]
      when class in ["ephemeral", "service", "transactional"] and tier in ["standard", "heavy"] ->
        :ok

      _ ->
        {:error, "not a HIPPO admission"}
    end
  end

  @doc "Checks the reviewed shape of a tailnet target command."
  def check_tailnet_shape("tailnet:up", "tailscale serve " <> rest) do
    if rest =~ ~r/^--bg --yes --https=443 --set-path=\/ 4100$/,
      do: :ok,
      else: {:error, "unexpected up flags"}
  end

  def check_tailnet_shape("tailnet:status", "tailscale serve status"), do: :ok

  def check_tailnet_shape("tailnet:down", "tailscale serve " <> rest) do
    if rest == "--https=443 --set-path=/ off", do: :ok, else: {:error, "unexpected down flags"}
  end

  def check_tailnet_shape(_, _), do: {:error, "not a Tailscale Serve command"}

  @doc "Splits the `;;` command list a scenario declares for an Nx target."
  def split_commands(commands) do
    commands |> String.split(";;") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  @doc "Checks the reviewed shape of an Nx target declaration."
  def check_target_shape(target, commands, depends, parallel) do
    with [_ | _] <- split_commands(commands),
         :ok <- check_depends(depends),
         :ok <- check_parallel(parallel) do
      {:ok, target}
    else
      _ -> {:error, "not an Nx target declaration"}
    end
  end

  defp check_depends("(none)"), do: :ok
  defp check_depends("test-data:cleanup"), do: :ok
  defp check_depends(_), do: {:error, "unexpected dependsOn"}

  defp check_parallel("false"), do: :ok
  defp check_parallel("(none)"), do: :ok
  defp check_parallel(_), do: {:error, "unexpected parallel"}
end
