defmodule BnestApp.Behaviour.DevelopmentCommands.UnitAdapter do
  @moduledoc """
  The unit layer's adapter for `development_commands.feature`. It drives the
  pure `BnestApp.Behaviour.DevelopmentCommandsModel` over the scenario's own
  data, so it proves the scenario logic without touching a file, socket, or
  process. Only the integration adapter reads the real repository files and
  runs the real target commands.
  """

  alias BnestApp.Behaviour.DevelopmentCommandsModel, as: Model

  @doc "Installs the model and this adapter in the scenario context."
  def install(context) do
    context
    |> Map.put(:commands_adapter, __MODULE__)
    |> Map.put(:commands, %{})
  end

  @doc "Nothing to release: the model is discarded with the scenario context."
  def release(context), do: context

  defp put_commands(context, patch),
    do: %{context | commands: Map.merge(context.commands, patch)}

  # Port ranges (BN-DOC-05).

  def allocate_server(context, server, first, last) do
    case Model.server_range(server) do
      %{first: ^first, last: ^last, bind: bind} ->
        unless Model.loopback?(bind), do: raise("#{inspect(server)} does not bind loopback")
        put_commands(context, %{server: server})

      _ ->
        raise "unknown server allocation for #{inspect(server)}"
    end
  end

  def configured_port(context, server, port) do
    if server != context.commands.server,
      do:
        raise(
          "port configured for #{inspect(server)} after allocating #{inspect(context.commands.server)}"
        )

    put_commands(context, %{port: port})
  end

  def assert_port_binding(context) do
    %{server: server, port: port} = context.commands
    %{first: first, last: last, bind: bind} = Model.server_range(server)

    unless Model.port_in_range?(first, last, port),
      do: raise("#{inspect(server)} port #{port} escapes #{first} to #{last}")

    unless Model.loopback?(bind), do: raise("#{inspect(server)} does not bind loopback")
    context
  end

  # The start command (BN-CLI-01, BN-CFG-02).

  def dev_port(context, "(unset)"), do: put_commands(context, %{dev_port: nil})
  def dev_port(context, value), do: put_commands(context, %{dev_port: value})

  def render_start(context) do
    put_commands(context, %{start_command: Model.render_start(context.commands[:dev_port])})
  end

  def assert_lease(context, port, min, max) do
    {:ok, lease} = Model.parse_hippo_lease(context.commands.start_command)

    unless lease.lease_port == port,
      do: raise("lease requests #{lease.lease_port}, expected #{port}")

    unless lease.owner == "development", do: raise("lease owner is #{lease.owner}")

    unless lease.min == min and lease.max == max,
      do: raise("lease range is #{lease.min} to #{lease.max}")

    unless lease.port == port, do: raise("PORT passes #{lease.port}, expected #{port}")
    context
  end

  def assert_endpoint(context, port, bind) do
    # The unit layer cannot read the endpoint configuration; it proves the
    # contract the integration adapter reads back from the real config files.
    unless Model.loopback?(bind), do: raise("the dev endpoint does not bind loopback")
    put_commands(context, %{endpoint_port: port})
  end

  # Test commands (BN-CLI-02, BN-CLI-03).

  def test_chain(context, script, chain) do
    put_commands(context, %{script: script, chain: chain})
  end

  def run_chain_with(context, failing) do
    {ran, skipped} = Model.run_chain(context.commands.chain, failing)
    put_commands(context, %{ran: ran, skipped: skipped, failing: failing})
  end

  def assert_chain(context) do
    # Re-derived from the chain string, not from the recorded run: the
    # targets after the failing one are the suffix that follows it.
    %{chain: chain, failing: failing, skipped: skipped} = context.commands
    targets = chain |> String.split(~r/\s+then\s+/) |> Enum.map(&String.trim/1)

    expected =
      case Enum.find_index(targets, &(&1 == failing)) do
        nil -> []
        index -> Enum.drop(targets, index + 1)
      end

    unless skipped == expected,
      do: raise("targets after the failure run: #{inspect(skipped)}")

    context
  end

  def assert_admission(context, _script, admission) do
    case Model.check_admission(admission) do
      :ok -> context
      {:error, reason} -> raise("admission #{inspect(admission)} refused: #{reason}")
    end
  end

  # Tailnet commands (BN-CLI-04).

  def declare_tailnet(context, target, command) do
    put_commands(context, %{target: target, command: command})
  end

  def run_tailnet(context) do
    %{target: target, command: command} = context.commands

    case Model.check_tailnet_shape(target, command) do
      :ok -> put_commands(context, %{recorded: command, double_status: 0, exit_status: 0})
      {:error, reason} -> raise("tailnet command refused: #{reason}")
    end
  end

  def assert_tailnet(context, expected) do
    %{command: command, recorded: recorded} = context.commands

    unless recorded == command and command == expected,
      do: raise("double recorded #{inspect(recorded)}, expected #{inspect(expected)}")

    # The target is the double's command line, so its exit status is the
    # double's for both the success and the failure double.
    for double_status <- [0, 1] do
      unless target_exit(double_status) == double_status,
        do: raise("target exits unlike the double")
    end

    put_commands(context, %{exit_status: context.commands.double_status})
  end

  defp target_exit(double_status), do: double_status

  # Nx targets (BN-CLI-27, BN-GATE-08).

  def declare_target(context, target, commands, depends, parallel) do
    put_commands(context, %{
      target: target,
      commands: commands,
      depends: depends,
      parallel: parallel
    })
  end

  def read_target(context) do
    %{target: target, commands: commands, depends: depends, parallel: parallel} = context.commands

    case Model.check_target_shape(target, commands, depends, parallel) do
      {:ok, _} -> put_commands(context, %{read_commands: Model.split_commands(commands)})
      {:error, reason} -> raise("target declaration refused: #{reason}")
    end
  end

  def assert_order(context) do
    %{commands: commands, read_commands: read} = context.commands

    unless read == Model.split_commands(commands) and read != [],
      do: raise("target does not run its commands in order")

    context
  end
end
