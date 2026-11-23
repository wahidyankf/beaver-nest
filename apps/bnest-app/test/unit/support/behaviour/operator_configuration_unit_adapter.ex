defmodule BnestApp.Behaviour.OperatorConfiguration.UnitAdapter do
  @moduledoc """
  The unit layer adapter for operator_configuration.feature.
  """

  alias BnestApp.Behaviour.OperatorConfigurationModel, as: Model
  alias BnestApp.Operations
  alias BnestApp.RuntimeSettings
  alias BnestApp.Test.InMemory.ReleaseEnvironment

  def install(context) do
    context
    |> Map.put(:operator_config_adapter, __MODULE__)
    |> Map.put(:operator_config, %{})
  end

  def release(context), do: context

  defp put_config(context, patch),
    do: %{context | operator_config: Map.merge(context.operator_config, patch)}

  def push_env(context, public_file, private_file, subject) do
    put_config(context, %{public_file: public_file, private_file: private_file, subject: subject})
  end

  def derive_push(context) do
    %{public_file: public_file, private_file: private_file, subject: subject} =
      context.operator_config

    env =
      %{}
      |> maybe_put("BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE", public_file)
      |> maybe_put("BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE", private_file)
      |> maybe_put("BNEST_WEB_PUSH_SUBJECT", subject)

    read = fn _path -> "" end

    outcome =
      try do
        _ = RuntimeSettings.push_config!(env, read)
        {:ok, :configured}
      rescue
        e in RuntimeError -> {:error, Exception.message(e)}
      end

    put_config(context, %{push_outcome: outcome})
  end

  defp maybe_put(env, _name, "(unset)"), do: env
  defp maybe_put(env, _name, ""), do: env
  defp maybe_put(env, name, value), do: Map.put(env, name, value)

  def assert_push(context, boot) do
    case context.operator_config.push_outcome do
      {:error, message} ->
        unless message == boot do
          raise "push boot raised #{message}, expected #{boot}"
        end

        context

      {:ok, _} ->
        raise "push boot succeeded, expected #{boot}"
    end
  end

  def stable_env(context, stable) do
    put_config(context, %{stable: stable})
  end

  def derive_dev(context) do
    %{stable: stable} = context.operator_config
    env = maybe_put(%{}, "BNEST_STABLE", stable)
    mode = RuntimeSettings.stable_mode?(env)
    put_config(context, %{stable_mode: mode})
  end

  def assert_dev(context, reload, watchers) do
    %{stable: stable, stable_mode: mode} = context.operator_config
    {exp_reload, exp_watchers} = Model.dev_config(stable)

    got_reload = if mode, do: :off, else: :on
    got_watchers = if mode, do: :none, else: :watchers

    unless got_reload == exp_reload and got_watchers == exp_watchers do
      raise "dev config mismatch"
    end

    unless to_string(got_reload) == reload do
      raise "reload is #{got_reload}, expected #{reload}"
    end

    want_watchers = if exp_watchers == :none, do: "none", else: "esbuild,Tailwind"

    unless watchers == want_watchers do
      raise "watchers are #{watchers}, expected #{want_watchers}"
    end

    context
  end

  def peer_env(context, peer, reachable) do
    put_config(context, %{peer: peer, reachable: reachable})
  end

  def check_readiness(context) do
    %{peer: peer, reachable: reachable} = context.operator_config
    env = ReleaseEnvironment.install()

    procs = [BnestApp.Storage.Records, BnestApp.Identity, BnestApp.CodexChat.ModelCatalog]
    Enum.each(procs, &ReleaseEnvironment.put_running(env, &1, true))

    case peer do
      "(unset)" -> ReleaseEnvironment.put_peer(env, nil, false)
      "" -> ReleaseEnvironment.put_peer(env, nil, false)
      named -> ReleaseEnvironment.put_peer(env, named, reachable == "yes")
    end

    liveness = Operations.liveness()
    readiness = Operations.readiness()
    health = Operations.health()
    put_config(context, %{liveness: liveness, readiness: readiness, health: health})
  end

  def assert_readiness(context, live, ready, health) do
    %{peer: peer, reachable: reachable} = context.operator_config
    {exp_live, exp_ready, exp_health} = Model.readiness(peer, reachable)

    unless to_string(exp_live) == live do
      raise "liveness mismatch"
    end

    unless to_string(exp_ready) == ready do
      raise "readiness mismatch"
    end

    want_health =
      case exp_health do
        :ready_200 -> "200 ready"
        :not_ready_503 -> health
      end

    unless health == want_health do
      raise "health is #{health}, expected #{want_health}"
    end

    assert_readiness_outcome(context, exp_ready)
  end

  defp assert_readiness_outcome(context, exp_ready) do
    case {context.operator_config.liveness, context.operator_config.readiness} do
      {{:ok, %{status: "live"}}, {:ok, %{status: "ready"}}} when exp_ready == :ready ->
        context

      {{:ok, %{status: "live"}}, {:error, :peer_unavailable}} when exp_ready == :not_ready ->
        context

      {{:ok, %{status: "live"}}, {:error, :not_ready}} when exp_ready == :not_ready ->
        context

      other ->
        raise "readiness outcome is #{inspect(other)}"
    end
  end

  def deploy_env(context, missing, origin) do
    put_config(context, %{missing: missing, origin: origin})
  end

  def attempt_prepare(context) do
    %{missing: missing, origin: origin} = context.operator_config

    message =
      if missing == "(none)" do
        case Model.origin_message(origin) do
          :ok -> :prepared
          msg -> msg
        end
      else
        Model.deploy_message(missing)
      end

    put_config(context, %{prepare: message})
  end

  def assert_prepare(context, message) do
    case context.operator_config.prepare do
      :prepared ->
        raise "prepare succeeded, expected #{message}"

      actual ->
        unless actual == message do
          raise "prepare refused #{actual}, expected #{message}"
        end

        context
    end
  end

  def cluster_env(context, query) do
    put_config(context, %{query: query})
  end

  def derive_cluster(context) do
    %{query: query} = context.operator_config
    env = maybe_put(%{}, "DNS_CLUSTER_QUERY", query)
    dns = RuntimeSettings.dns_cluster_query(env)
    child = RuntimeSettings.dns_cluster_child(dns)
    put_config(context, %{dns: dns, child: child})
  end

  def assert_cluster(context, cluster) do
    %{query: query, child: child} = context.operator_config

    case Model.cluster_for(query) do
      :no_cluster ->
        unless child == {DNSCluster, [query: :ignore]} do
          raise "cluster should be ignored"
        end

        unless cluster == "no cluster" do
          raise "cluster is not #{cluster}"
        end

        context

      {:dns, _q} ->
        unless match?({DNSCluster, [query: _]}, child) do
          raise "cluster child mismatch"
        end

        unless String.starts_with?(cluster, "DNS ") do
          raise "cluster is not #{cluster}"
        end

        context
    end
  end

  def transport_env(context, host, scheme) do
    put_config(context, %{host: host, scheme: scheme})
  end

  def derive_transport(context) do
    %{host: host, scheme: scheme} = context.operator_config
    decision = Model.transport(host, scheme)
    put_config(context, %{decision: decision})
  end

  def assert_transport(context, bind, answer) do
    %{host: host, scheme: scheme, decision: decision} = context.operator_config
    expected = Model.transport(host, scheme)

    unless decision == expected do
      raise "transport mismatch"
    end

    want_answer = if expected == :redirect, do: "redirect to HTTPS + HSTS", else: "serve"

    unless answer == want_answer do
      raise "answer is #{answer}, expected #{want_answer}"
    end

    unless Model.loopback_bind?(bind) do
      raise "bind is not loopback"
    end

    context
  end
end
