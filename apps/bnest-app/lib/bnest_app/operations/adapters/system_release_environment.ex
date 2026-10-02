defmodule BnestApp.Operations.Adapters.SystemReleaseEnvironment do
  @moduledoc """
  The `BnestApp.Operations.Ports.ReleaseEnvironment` of the running node: the deployment's
  `BNEST_RELEASE_REVISION`, `BNEST_DEPLOY_SLOT` and `BNEST_DEPLOY_PEER` environment
  variables, the local process registry, and a distribution ping of the peer node.
  """

  @behaviour BnestApp.Operations.Ports.ReleaseEnvironment

  @impl true
  def new, do: %{adapter: __MODULE__}

  @impl true
  def revision(_environment), do: System.get_env("BNEST_RELEASE_REVISION")

  @impl true
  def slot(_environment), do: System.get_env("BNEST_DEPLOY_SLOT")

  @impl true
  def peer(_environment), do: System.get_env("BNEST_DEPLOY_PEER")

  @impl true
  def running?(_environment, name), do: Process.whereis(name) != nil

  @impl true
  def peer_reachable?(_environment, peer),
    do: Node.alive?() and Node.ping(String.to_atom(peer)) == :pong
end
