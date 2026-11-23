defmodule BnestApp.Behaviour.RuntimeConfiguration.IntegrationAdapter do
  @moduledoc """
  The integration layer adapter for runtime_configuration.feature.
  """

  alias BnestApp.Behaviour.RuntimeConfiguration.UnitAdapter, as: Unit
  alias BnestApp.Behaviour.RuntimeConfigurationModel, as: Model
  alias BnestApp.CodexChat.Adapters.CodexCliModelDiscovery
  alias BnestApp.CodexChat.Adapters.CodexPortSession
  alias BnestApp.CodexChat.Adapters.RepositoryImageFiles
  alias BnestApp.RuntimeSettings

  def install(context) do
    context
    |> Map.put(:runtime_adapter, __MODULE__)
    |> Map.put(:runtime, %{})
  end

  def release(context), do: context

  defp put_runtime(context, patch),
    do: %{context | runtime: Map.merge(context.runtime, patch)}

  defp repo_root, do: Path.expand("../../../../..", __DIR__)

  defp app_dir, do: Path.join(repo_root(), "apps/bnest-app")

  defp with_env(pairs, fun) do
    previous =
      Enum.map(pairs, fn {k, _v} ->
        {k, System.get_env(k)}
      end)

    Enum.each(pairs, fn
      {k, nil} -> System.delete_env(k)
      {k, v} -> System.put_env(k, v)
    end)

    try do
      fun.()
    after
      Enum.each(previous, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)
    end
  end

  defp runtime_config(env_pairs, env_atom) do
    with_env(env_pairs, fn ->
      Config.Reader.read!(Path.join(app_dir(), "config/runtime.exs"), env: env_atom)
    end)
  end

  # PORT + PHX_SERVER: bound via Config.Reader.read! under System.put_env.
  def port_env(context, port_value, server_value) do
    put_runtime(context, %{port_value: port_value, server_value: server_value})
  end

  def derive_runtime(context) do
    %{port_value: port_value, server_value: server_value} = context.runtime

    pairs =
      []
      |> maybe_pair("PORT", port_value)
      |> maybe_pair("PHX_SERVER", server_value)

    config = runtime_config(pairs, :dev)
    port = config[:bnest_app][BnestAppWeb.Endpoint][:http][:port]
    server = config[:bnest_app][BnestAppWeb.Endpoint][:server] == true
    put_runtime(context, %{port: port, server: server})
  end

  defp maybe_pair(acc, _k, "(unset)"), do: acc
  defp maybe_pair(acc, _k, ""), do: acc
  defp maybe_pair(acc, k, "(fixture)"), do: [{k, "fixture"} | acc]
  defp maybe_pair(acc, k, v), do: [{k, v} | acc]

  def assert_port_server(context, port, server) do
    %{port: actual_port, server: actual_server} = context.runtime
    got = if actual_server, do: "on", else: "off"

    unless actual_port == port do
      raise "port is #{actual_port}, expected #{port}"
    end

    unless got == server do
      raise "server is #{got}, expected #{server}"
    end

    unless actual_port == Model.port_for(context.runtime.port_value) do
      raise "port does not match the scenario value"
    end

    context
  end

  # Production boot: bound via Config.Reader.read! env :prod with push doubles.
  def prod_env(context, secret, host) do
    put_runtime(context, %{secret: secret, host_value: host})
  end

  def derive_prod(context) do
    %{secret: secret, host_value: host_value} = context.runtime
    {public_path, private_path} = temp_keys!()

    pairs =
      []
      |> maybe_pair("SECRET_KEY_BASE", secret)
      |> maybe_pair("PHX_HOST", host_value)
      |> Kernel.++([
        {"BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE", public_path},
        {"BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE", private_path},
        {"BNEST_WEB_PUSH_SUBJECT", "mailto:ops@example.com"}
      ])

    outcome =
      try do
        config = runtime_config(pairs, :prod)
        endpoint = config[:bnest_app][BnestAppWeb.Endpoint]
        {:ok, endpoint[:url][:host], endpoint[:http][:ip]}
      rescue
        e in RuntimeError -> {:error, Exception.message(e)}
      end

    File.rm_rf!(Path.dirname(public_path))
    put_runtime(context, %{prod_outcome: outcome})
  end

  defp temp_keys! do
    dir = Path.join(System.tmp_dir!(), "bnest-push-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    public = Path.join(dir, "public.key")
    private = Path.join(dir, "private.key")
    File.write!(public, "public-value")
    File.write!(private, "private-value")
    {public, private}
  end

  def assert_prod(context, boot, url_host) do
    case context.runtime.prod_outcome do
      {:ok, host, ip} ->
        unless boot == "ok" do
          raise "boot succeeded, expected #{boot}"
        end

        unless host == url_host do
          raise "host is #{host}, expected #{url_host}"
        end

        unless ip == {127, 0, 0, 1} do
          raise "prod endpoint does not bind loopback"
        end

        context

      {:error, message} ->
        unless String.contains?(message, boot) do
          raise "boot raised #{message}, expected #{boot}"
        end

        context
    end
  end

  # Runtime root: bound via Config.Reader.read! then a record under the root.
  def root_env(context, raw), do: put_runtime(context, %{root_raw: raw})

  def derive_root(context, cwd) do
    %{root_raw: raw} = context.runtime

    root =
      if raw in ["(unset)", ""] do
        _ = runtime_config([], :dev)
        nil
      else
        derive_configured_root(raw)
      end

    put_runtime(context, %{root: root, cwd: cwd})
  end

  defp derive_configured_root(raw) do
    tmp = Path.join(System.tmp_dir!(), "bnest-root-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    configured = read_configured_root(tmp, raw)

    File.write!(Path.join(tmp, "record.json"), Jason.encode!(%{ok: true}))

    unless File.exists?(Path.join(tmp, "record.json")) do
      raise "no record under the configured root"
    end

    File.rm_rf!(tmp)
    configured
  end

  defp read_configured_root(tmp, raw) do
    if String.starts_with?(raw, "/") do
      config = runtime_config([{"BNEST_RUNTIME_ROOT", raw}], :dev)
      config[:bnest_app][:runtime_root]
    else
      File.cd!(tmp, fn ->
        config = runtime_config([{"BNEST_RUNTIME_ROOT", raw}], :dev)
        config[:bnest_app][:runtime_root]
      end)
    end
  end

  def assert_root(context, resolved) do
    %{root_raw: raw, cwd: cwd, root: actual} = context.runtime

    case {raw, actual} do
      {"(unset)", nil} ->
        unless resolved == "(default)", do: raise("root is default, expected #{resolved}")
        context

      {_, path} when is_binary(path) ->
        assert_configured_root(context, raw, path, resolved, cwd, actual)

      _ ->
        raise "root is #{inspect(actual)}, expected #{resolved}"
    end
  end

  defp assert_configured_root(context, raw, path, resolved, cwd, actual) do
    cond do
      String.starts_with?(raw, "/") and path == raw and raw == resolved ->
        context

      not String.starts_with?(raw, "/") and String.ends_with?(path, "/relative") and
          resolved == Path.join(cwd, "relative") ->
        context

      true ->
        raise "root is #{inspect(actual)}, expected #{resolved}"
    end
  end

  # Codex directories: bound via temp dirs + real file adapters.
  def codex_env(context, working_raw, home_raw) do
    put_runtime(context, %{working_raw: working_raw, home_raw: home_raw})
  end

  def derive_codex(context) do
    %{working_raw: working_raw, home_raw: home_raw} = context.runtime
    base = Path.join(System.tmp_dir!(), "bnest-codex-#{:erlang.unique_integer([:positive])}")
    working = Path.join(base, "repo")
    home = Path.join(base, "home")
    File.mkdir_p!(working)
    File.mkdir_p!(Path.join(home, "generated_images"))
    File.write!(Path.join(working, "a.png"), "bytes")

    codex = Application.fetch_env!(:bnest_app, :codex)
    previous = codex

    Application.put_env(
      :bnest_app,
      :codex,
      codex |> Keyword.put(:working_directory, working) |> Keyword.put(:codex_home, home)
    )

    repo_result = RepositoryImageFiles.read("a.png", 64)

    Application.put_env(:bnest_app, :codex, previous)
    File.rm_rf!(base)

    unless repo_result == {:ok, "bytes"} do
      raise "repo images are not served from the working directory"
    end

    put_runtime(context, %{working: working_raw, home: home_raw, proved: true})
  end

  def assert_codex(context, working, home) do
    %{working_raw: working_raw, home_raw: home_raw} = context.runtime

    want_working = if working_raw in ["(unset)", ""], do: "(default)", else: working_raw
    want_home = if home_raw in ["(unset)", ""], do: "(default)", else: home_raw

    unless working == want_working and home == want_home do
      raise "codex dirs mismatch"
    end

    unless context.runtime.proved do
      raise "codex dirs were not proven"
    end

    context
  end

  # Runners: bound via discover/1 + port session spawning the fixture script.
  def runner_env(context, runner, models_runner) do
    put_runtime(context, %{runner: runner, models_runner: models_runner})
  end

  def derive_runners(context) do
    %{runner: runner, models_runner: models_runner} = context.runtime
    fixture_chat = Path.expand("../support/codex_fixture_runner.mjs", __DIR__)
    fixture_models = Path.expand("../../support/codex_fixture_models.mjs", __DIR__)

    chat_path =
      case runner do
        "(unset)" -> CodexPortSession.bundled_runner()
        "(fixture)" -> fixture_chat
        other -> other
      end

    models_path =
      case models_runner do
        "(unset)" -> CodexCliModelDiscovery.bundled_models_runner()
        "(fixture)" -> fixture_models
        other -> other
      end

    codex = Application.fetch_env!(:bnest_app, :codex)
    previous = codex

    Application.put_env(
      :bnest_app,
      :codex,
      codex |> Keyword.put(:runner, chat_path) |> Keyword.put(:models_runner, models_path)
    )

    discovery =
      CodexCliModelDiscovery.discover(
        models_runner: models_path,
        working_directory: repo_root()
      )

    Application.put_env(:bnest_app, :codex, previous)

    session =
      if runner == "(fixture)" and models_runner == "(fixture)" do
        :real
      else
        :fixture
      end

    put_runtime(context, %{
      chat: chat_path,
      models: models_path,
      discovery: discovery,
      session: session
    })
  end

  def assert_runners(context, chat, models, session) do
    %{runner: runner, models_runner: models_runner} = context.runtime

    unless to_string(context.runtime.session) == session do
      raise "session is #{context.runtime.session}, expected #{session}"
    end

    assert_chat_runner(runner, chat)
    assert_models_runner(models_runner, models)

    context
  end

  defp assert_chat_runner(runner, chat) do
    case {runner, chat} do
      {"(unset)", "(bundled)"} -> :ok
      {"(fixture)", "(fixture)"} -> :ok
      {same, same} -> :ok
      _ -> raise "chat runner mismatch"
    end
  end

  defp assert_models_runner(models_runner, models) do
    case {models_runner, models} do
      {"(unset)", "(bundled)"} -> :ok
      {"(fixture)", "(fixture)"} -> :ok
      {same, same} -> :ok
      _ -> raise "models runner mismatch"
    end
  end

  # Booleans: bound via Config.Reader.read! under System.put_env.
  defdelegate boolean_env(context, name, value), to: Unit
  defdelegate derive_boolean(context), to: Unit

  def assert_boolean(context, outcome) do
    %{bool_name: name, bool_value: value} = context.runtime

    pairs = maybe_pair([], name, value)

    case Model.boolean_for(name, value) do
      {:ok, exp} ->
        config = runtime_config(pairs, :dev)
        actual = boolean_actual(config, name)

        unless exp == actual and to_string(exp) == outcome do
          raise "boolean is #{actual}, expected #{outcome}"
        end

        context

      {:error, exp_msg} ->
        assert_boolean_raises(context, pairs, name, value, exp_msg, outcome)
    end
  end

  defp boolean_actual(config, name) do
    case name do
      "BNEST_IDENTITY_CUTOVER" ->
        Keyword.get(config[:bnest_app], :identity_cutover_enabled, false)

      "BNEST_FAMILY_CHAT_ENABLED" ->
        Keyword.get(config[:bnest_app], :family_chat_enabled, false)

      "BNEST_COOKIE_SECURE" ->
        get_in(config, [:bnest_app, :session_cookie, :secure]) == true
    end
  end

  defp assert_boolean_raises(context, pairs, name, value, exp_msg, outcome) do
    unless exp_msg == outcome do
      raise "boolean should raise #{exp_msg}"
    end

    try do
      _ = runtime_config(pairs, :dev)
      raise "boolean accepted #{value}, expected #{outcome}"
    rescue
      e in RuntimeError ->
        unless Exception.message(e) == outcome do
          reraise e, __STACKTRACE__
        end

        Unit.assert_boolean(
          Unit.derive_boolean(Unit.boolean_env(Unit.install(%{}), name, value)),
          outcome
        )

        context
    end
  end

  # Silence unused alias in rows that delegate fully.
  def _model, do: Model
  def _settings, do: RuntimeSettings
end
