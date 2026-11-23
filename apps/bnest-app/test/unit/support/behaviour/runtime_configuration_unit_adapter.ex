defmodule BnestApp.Behaviour.RuntimeConfiguration.UnitAdapter do
  @moduledoc """
  The unit layer adapter for runtime_configuration.feature.
  """

  alias BnestApp.Behaviour.RuntimeConfigurationModel, as: Model
  alias BnestApp.RuntimeSettings

  def install(context) do
    context
    |> Map.put(:runtime_adapter, __MODULE__)
    |> Map.put(:runtime, %{})
  end

  def release(context), do: context

  defp put_runtime(context, patch),
    do: %{context | runtime: Map.merge(context.runtime, patch)}

  defp env_of(values) do
    Enum.reduce(values, %{}, fn
      {_k, "(unset)"}, acc -> acc
      {_k, ""}, acc -> acc
      {k, v}, acc -> Map.put(acc, k, v)
    end)
  end

  defp expand_with(cwd) do
    fn raw ->
      if String.starts_with?(raw, "/") do
        raw
      else
        cwd <> "/" <> raw
      end
    end
  end

  def port_env(context, port_value, server_value) do
    put_runtime(context, %{port_value: port_value, server_value: server_value})
  end

  def derive_runtime(context) do
    %{port_value: port_value, server_value: server_value} = context.runtime
    env = env_of([{"PORT", port_value}, {"PHX_SERVER", server_value}])
    port = RuntimeSettings.http_port(env)
    server = RuntimeSettings.server_enabled?(env)
    put_runtime(context, %{port: port, server: server})
  end

  def assert_port_server(context, port, server) do
    %{port: actual_port, server: actual_server} = context.runtime
    expected_server = Model.server_for(context.runtime.server_value)

    unless actual_port == port do
      raise "port is #{actual_port}, expected #{port}"
    end

    unless actual_port == Model.port_for(context.runtime.port_value) do
      raise "port does not match the scenario value"
    end

    got = if actual_server, do: "on", else: "off"

    unless got == server and expected_server == actual_server do
      raise "server is #{got}, expected #{server}"
    end

    context
  end

  def prod_env(context, secret, host) do
    put_runtime(context, %{secret: secret, host_value: host})
  end

  def derive_prod(context) do
    %{secret: secret, host_value: host_value} = context.runtime

    boot =
      case Model.prod_boot(secret, host_value) do
        {:error, message} -> {:error, message}
        {:ok, url_host} -> {:ok, url_host}
      end

    env = env_of([{"SECRET_KEY_BASE", secret}, {"PHX_HOST", host_value}])

    checked =
      try do
        _ = RuntimeSettings.secret_key_base!(env)
        {:ok, RuntimeSettings.phx_host(env)}
      rescue
        e in RuntimeError -> {:error, Exception.message(e)}
      end

    put_runtime(context, %{boot: boot, checked: checked})
  end

  def assert_prod(context, boot, url_host) do
    %{boot: {:ok, actual_host}, checked: {:ok, checked_host}} =
      case context.runtime.boot do
        {:ok, _} -> context.runtime
        {:error, message} -> raise "boot raised #{message}, expected #{boot}"
      end

    unless boot == "ok" do
      raise "boot is ok, expected #{boot}"
    end

    assert_prod_hosts(actual_host, checked_host, url_host, context)

    context
  rescue
    e ->
      %{boot: boot_result} = context.runtime

      case boot_result do
        {:error, message} ->
          unless String.contains?(message, boot) do
            reraise e, __STACKTRACE__
          end

          context

        {:ok, _} ->
          reraise e, __STACKTRACE__
      end
  end

  defp assert_prod_hosts(actual_host, checked_host, url_host, context) do
    unless actual_host == url_host and checked_host == url_host do
      raise "host is #{actual_host}, expected #{url_host}"
    end

    unless Model.prod_host(context.runtime.host_value) == url_host do
      raise "host does not match the scenario value"
    end

    :ok
  end

  def root_env(context, raw) do
    put_runtime(context, %{root_raw: raw})
  end

  def derive_root(context, cwd) do
    %{root_raw: raw} = context.runtime
    env = env_of([{"BNEST_RUNTIME_ROOT", raw}])
    expand = expand_with(cwd)
    root = RuntimeSettings.runtime_root(env, expand)
    put_runtime(context, %{root: root, cwd: cwd})
  end

  def assert_root(context, resolved) do
    %{root_raw: raw, cwd: cwd, root: actual} = context.runtime
    expected = Model.runtime_expected(raw, cwd, expand_with(cwd))

    case {expected, actual} do
      {:default, nil} ->
        if resolved == "(default)" do
          context
        else
          raise "root is default, expected #{resolved}"
        end

      {exp, act} when exp == act ->
        if act == resolved do
          context
        else
          raise "root is #{act}, expected #{resolved}"
        end

      _ ->
        raise "root mismatch"
    end
  end

  def codex_env(context, working_raw, home_raw) do
    put_runtime(context, %{working_raw: working_raw, home_raw: home_raw})
  end

  def derive_codex(context) do
    %{working_raw: working_raw, home_raw: home_raw} = context.runtime
    env = env_of([{"BNEST_CODEX_WORKING_DIRECTORY", working_raw}, {"BNEST_CODEX_HOME", home_raw}])
    expand = expand_with("/srv")
    working = RuntimeSettings.codex_working_directory(env, expand)
    home = RuntimeSettings.codex_home(env, expand)
    put_runtime(context, %{working: working, home: home})
  end

  def assert_codex(context, working, home) do
    %{working_raw: working_raw, home_raw: home_raw, working: actual_working, home: actual_home} =
      context.runtime

    unless Model.codex_expected(working_raw) == codex_marker(working_raw, actual_working) do
      raise "working directory mismatch"
    end

    unless Model.codex_expected(home_raw) == codex_marker(home_raw, actual_home) do
      raise "codex home mismatch"
    end

    unless working == expected_codex(working_raw, actual_working) do
      raise "working is not #{working}"
    end

    unless home == expected_codex(home_raw, actual_home) do
      raise "home is not #{home}"
    end

    context
  end

  defp codex_marker("(unset)", nil), do: :default
  defp codex_marker("", nil), do: :default
  defp codex_marker(raw, _expanded), do: {:expanded, raw}

  defp expected_codex("(unset)", nil), do: "(default)"
  defp expected_codex("", nil), do: "(default)"
  defp expected_codex(_raw, expanded), do: expanded

  def runner_env(context, runner, models_runner) do
    put_runtime(context, %{runner: runner, models_runner: models_runner})
  end

  def derive_runners(context) do
    %{runner: runner, models_runner: models_runner} = context.runtime
    env = env_of([{"BNEST_CODEX_RUNNER", runner}, {"BNEST_CODEX_MODELS_RUNNER", models_runner}])
    chat = RuntimeSettings.codex_runner(env, "bundled-chat")
    models = RuntimeSettings.codex_models_runner(env, "bundled-models")
    same? = fn a, b -> a == b end

    session =
      RuntimeSettings.fixture_runner?(Map.get(env, "BNEST_CODEX_RUNNER"), "bundled-chat", same?)

    put_runtime(context, %{chat: chat, models: models, fixture: session})
  end

  def assert_runners(context, chat, models, session) do
    %{runner: runner, models_runner: models_runner} = context.runtime

    unless Model.chat_expected(runner) == chat_marker(runner, context.runtime.chat) do
      raise "chat runner mismatch"
    end

    unless Model.models_expected(models_runner) ==
             chat_marker(models_runner, context.runtime.models) do
      raise "models runner mismatch"
    end

    unless Model.session_for(runner_tag(runner), runner_tag(models_runner)) ==
             session_atom(session) do
      raise "session is not #{session}"
    end

    unless chat == expected_runner(runner, context.runtime.chat) do
      raise "chat is not #{chat}"
    end

    unless models == expected_runner(models_runner, context.runtime.models) do
      raise "models are not #{models}"
    end

    context
  end

  defp chat_marker("(unset)", "bundled-chat"), do: :bundled
  defp chat_marker("(unset)", "bundled-models"), do: :bundled
  defp chat_marker("(fixture)", _), do: :fixture
  defp chat_marker(raw, _), do: {:path, raw}

  defp runner_tag("(fixture)"), do: "(fixture)"
  defp runner_tag("(unset)"), do: "(unset)"
  defp runner_tag(other), do: other

  defp session_atom("fixture"), do: :fixture
  defp session_atom("real"), do: :real

  defp expected_runner("(unset)", _actual), do: "(bundled)"
  defp expected_runner("(fixture)", _actual), do: "(fixture)"
  defp expected_runner(_raw, actual), do: actual

  def boolean_env(context, name, value) do
    put_runtime(context, %{bool_name: name, bool_value: value})
  end

  def derive_boolean(context) do
    %{bool_name: name, bool_value: value} = context.runtime
    env = env_of([{name, value}])

    outcome =
      try do
        {:ok, RuntimeSettings.boolean_setting!(env, name, false)}
      rescue
        e in RuntimeError -> {:error, Exception.message(e)}
      end

    put_runtime(context, %{bool_outcome: outcome})
  end

  def assert_boolean(context, outcome) do
    %{bool_name: name, bool_value: value, bool_outcome: actual} = context.runtime
    expected = Model.boolean_for(name, value)

    case {expected, actual} do
      {{:ok, exp}, {:ok, act}} ->
        unless exp == act and to_string(act) == outcome do
          raise "boolean is #{act}, expected #{outcome}"
        end

        context

      {{:error, exp_msg}, {:error, act_msg}} ->
        unless exp_msg == act_msg and act_msg == outcome do
          raise "boolean raised #{act_msg}, expected #{outcome}"
        end

        context

      _ ->
        raise "boolean outcome mismatch"
    end
  end
end
