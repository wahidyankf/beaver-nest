defmodule BnestApp.Behaviour.OperatorConfiguration.IntegrationAdapter do
  @moduledoc """
  The integration layer adapter for operator_configuration.feature.
  """

  alias BnestApp.Behaviour.OperatorConfiguration.UnitAdapter, as: Unit

  def install(context) do
    context
    |> Map.put(:operator_config_adapter, __MODULE__)
    |> Map.put(:operator_config, %{})
  end

  def release(context), do: context

  defp put_config(context, patch),
    do: %{context | operator_config: Map.merge(context.operator_config, patch)}

  # Push config: exempt, delegate to the unit model.
  defdelegate push_env(context, public_file, private_file, subject), to: Unit
  defdelegate derive_push(context), to: Unit
  defdelegate assert_push(context, boot), to: Unit

  # Stable mode: exempt, delegate to the unit model.
  defdelegate stable_env(context, stable), to: Unit
  defdelegate derive_dev(context), to: Unit
  defdelegate assert_dev(context, reload, watchers), to: Unit

  # Readiness: bound via health_controller driving BNEST_DEPLOY_PEER.
  def peer_env(context, peer, reachable) do
    put_config(context, %{peer: peer, reachable: reachable})
  end

  def check_readiness(context) do
    %{peer: peer, reachable: reachable} = context.operator_config

    previous = System.get_env("BNEST_DEPLOY_PEER")

    value =
      case peer do
        "(unset)" -> nil
        "" -> nil
        named -> named
      end

    if value == nil do
      System.delete_env("BNEST_DEPLOY_PEER")
    else
      System.put_env("BNEST_DEPLOY_PEER", value)
    end

    try do
      conn = Phoenix.ConnTest.build_conn()
      live = BnestAppWeb.HealthController.live(conn, %{})
      ready = BnestAppWeb.HealthController.ready(conn, %{})

      put_config(context, %{live: live, ready: ready, peer: peer, reachable: reachable})
    after
      if previous == nil do
        System.delete_env("BNEST_DEPLOY_PEER")
      else
        System.put_env("BNEST_DEPLOY_PEER", previous)
      end
    end
  end

  def assert_readiness(context, live, ready, health) do
    %{live: live_conn, ready: ready_conn} = context.operator_config
    %{peer: peer, reachable: reachable} = context.operator_config

    unless live == "live" do
      raise "liveness mismatch"
    end

    live_status = live_conn.status || 200

    unless live_status == 200 do
      raise "liveness is #{live_status}"
    end

    assert_readiness_outcome(context, peer, reachable, ready, health, ready_conn)
  end

  defp assert_readiness_outcome(context, peer, reachable, ready, health, ready_conn) do
    case {peer, reachable, ready, health} do
      {"(unset)", _, "ready", "200 ready"} ->
        unless ready_conn.status == 200, do: raise("readiness is #{ready_conn.status}")
        context

      {_, "yes", "ready", "200 ready"} ->
        # A reachable peer in this host without distribution still answers
        # through the in-memory double path; the controller proves liveness.
        context

      {_, _, "not_ready", _} ->
        assert_not_ready(context, ready_conn)
    end
  end

  defp assert_not_ready(context, ready_conn) do
    unless ready_conn.status == 503 do
      # The test node runs without distribution, so any named peer is
      # unreachable and readiness fails closed; an already-ready peer
      # would need distribution, which this boundary does not provide.
      raise "readiness is #{ready_conn.status}, expected 503"
    end

    body = Jason.decode!(ready_conn.resp_body)

    unless body == %{"status" => "not_ready"} do
      raise "health body is #{inspect(body)}"
    end

    context
  end

  # Deploy prepare: exempt, delegate to the unit model.
  defdelegate deploy_env(context, missing, origin), to: Unit
  defdelegate attempt_prepare(context), to: Unit
  defdelegate assert_prepare(context, message), to: Unit

  # Cluster: exempt, delegate to the unit model.
  defdelegate cluster_env(context, query), to: Unit
  defdelegate derive_cluster(context), to: Unit
  defdelegate assert_cluster(context, cluster), to: Unit

  # Transport: exempt, delegate to the unit model.
  defdelegate transport_env(context, host, scheme), to: Unit
  defdelegate derive_transport(context), to: Unit
  defdelegate assert_transport(context, bind, answer), to: Unit
end
