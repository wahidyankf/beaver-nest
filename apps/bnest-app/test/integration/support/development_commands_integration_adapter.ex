defmodule BnestApp.Behaviour.DevelopmentCommands.IntegrationAdapter do
  @moduledoc """
  The integration layer's adapter for `development_commands.feature`. Where
  the review binds a scenario at integration, it reads the real repository
  files and runs the real target commands: the endpoint configuration comes
  back from `Config.Reader`, the tailnet targets run against a recording
  doubles. Where the review exempts integration, it delegates to the same
  pure model the unit adapter drives, since no integration boundary observes
  the exempt behaviour.
  """

  alias BnestApp.Behaviour.DevelopmentCommands.UnitAdapter, as: Unit
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

  defp repo_root, do: Path.expand("../../../../..", __DIR__)

  defp read_json(path) do
    path |> File.read!() |> Jason.decode!()
  end

  # Port ranges (BN-DOC-05): exempt, so the pure model proves the logic.
  defdelegate allocate_server(context, server, first, last), to: Unit
  defdelegate configured_port(context, server, port), to: Unit
  defdelegate assert_port_binding(context), to: Unit

  # The start command (BN-CLI-01): bound, so the endpoint configuration is
  # read back from the real config files.
  defdelegate dev_port(context, value), to: Unit

  def render_start(context) do
    port =
      if context.commands[:dev_port] in [nil, ""], do: "4020", else: context.commands.dev_port

    script = read_json(Path.join(repo_root(), "package.json"))["scripts"]["start"]

    command =
      script
      |> String.replace("${BNEST_DEV_PORT:-4020}", port)
      |> String.replace("./hippo", "hippo")

    put_commands(context, %{start_command: command, endpoint_port: String.to_integer(port)})
  end

  defdelegate assert_lease(context, port, min, max), to: Unit

  def assert_endpoint(context, port, bind) do
    unless Model.loopback?(bind), do: raise("the dev endpoint does not bind loopback")
    expected = context.commands.endpoint_port || port
    previous = System.get_env("PORT")
    System.put_env("PORT", Integer.to_string(expected))

    try do
      app = Path.join(repo_root(), "apps/bnest-app")

      runtime = Config.Reader.read!(Path.join(app, "config/runtime.exs"), env: :dev)
      dev = Config.Reader.read!(Path.join(app, "config/dev.exs"), env: :dev)

      actual_port = runtime[:bnest_app][BnestAppWeb.Endpoint][:http][:port]
      actual_ip = dev[:bnest_app][BnestAppWeb.Endpoint][:http][:ip]

      unless actual_port == expected,
        do: raise("the dev endpoint listens on #{actual_port}, expected #{expected}")

      unless actual_ip == {127, 0, 0, 1},
        do: raise("the dev endpoint binds #{inspect(actual_ip)}, expected loopback")

      context
    after
      if previous == nil, do: System.delete_env("PORT"), else: System.put_env("PORT", previous)
    end
  end

  # Test commands (BN-CLI-02, BN-CLI-03): exempt, so the pure model proves
  # the logic.
  defdelegate test_chain(context, script, chain), to: Unit
  defdelegate run_chain_with(context, failing), to: Unit
  defdelegate assert_chain(context), to: Unit
  defdelegate assert_admission(context, script, admission), to: Unit

  # Tailnet commands (BN-CLI-04): bound, so the target command is read back
  # from the real project file and run against a recording double.
  def declare_tailnet(context, target, command) do
    actual =
      read_json(Path.join(repo_root(), "apps/bnest-app/project.json"))["targets"][target][
        "command"
      ]

    unless actual == command,
      do:
        raise(
          "project.json declares #{inspect(actual)} for #{target}, expected #{inspect(command)}"
        )

    put_commands(context, %{target: target, command: command})
  end

  def run_tailnet(context) do
    %{command: command} = context.commands

    double_dir =
      Path.join(System.tmp_dir!(), "bnest-tailnet-#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(double_dir)
    log = Path.join(double_dir, "argv.log")

    try do
      File.write!(
        Path.join(double_dir, "tailscale"),
        "#!/bin/sh\necho \"$@\" > \"#{log}\"\nexit ${TAILSCALE_STATUS:-0}\n"
      )

      File.chmod!(Path.join(double_dir, "tailscale"), 0o755)

      for status <- ["0", "1"] do
        {_, exit_status} =
          System.cmd("sh", ["-c", command],
            env: %{
              "PATH" => "#{double_dir}:#{System.get_env("PATH")}",
              "TAILSCALE_STATUS" => status
            },
            stderr_to_stdout: true
          )

        unless exit_status == String.to_integer(status),
          do: raise("target exits #{exit_status} with a double exiting #{status}")

        unless File.read!(log) |> String.trim() == String.trim_leading(command, "tailscale "),
          do: raise("double recorded something else")
      end

      put_commands(context, %{recorded: command, double_status: 0, exit_status: 0})
    after
      File.rm_rf!(double_dir)
    end
  end

  defdelegate assert_tailnet(context, expected), to: Unit

  # Nx targets (BN-CLI-27, BN-GATE-08): exempt, so the pure model proves the
  # logic.
  defdelegate declare_target(context, target, commands, depends, parallel), to: Unit
  defdelegate read_target(context), to: Unit
  defdelegate assert_order(context), to: Unit
end
