defmodule BnestApp.Operations.Ports.ReleaseEnvironment do
  @moduledoc """
  The environment a running release reports from: the revision and deployment slot the
  deployment named, whether a named local process runs, and the peer slot it may need to
  reach during a promotion.

  Every callback except `new/0` takes the environment's handle first. The handle is a map
  whose `:adapter` key names the implementing module.

  Semantics every implementation keeps:

    * `revision/1`, `slot/1` and `peer/1` return the value the deployment set, or nil when
      it set none. An empty value is returned as is; the application decides what nil and
      an empty value mean.
    * `running?/2` holds while a process is registered locally under `name`.
    * `peer_reachable?/2` holds when this node runs distributed and the peer node `peer`
      answers a ping.
  """

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}

  @doc "A handle over the environment the running release serves from."
  @callback new() :: handle()

  @callback revision(handle()) :: String.t() | nil
  @callback slot(handle()) :: String.t() | nil
  @callback peer(handle()) :: String.t() | nil
  @callback running?(handle(), name :: atom()) :: boolean()
  @callback peer_reachable?(handle(), peer :: String.t()) :: boolean()

  @spec revision(handle()) :: String.t() | nil
  def revision(environment), do: environment.adapter.revision(environment)

  @spec slot(handle()) :: String.t() | nil
  def slot(environment), do: environment.adapter.slot(environment)

  @spec peer(handle()) :: String.t() | nil
  def peer(environment), do: environment.adapter.peer(environment)

  @spec running?(handle(), atom()) :: boolean()
  def running?(environment, name), do: environment.adapter.running?(environment, name)

  @spec peer_reachable?(handle(), String.t()) :: boolean()
  def peer_reachable?(environment, peer),
    do: environment.adapter.peer_reachable?(environment, peer)
end
