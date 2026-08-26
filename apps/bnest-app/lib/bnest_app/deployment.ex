defmodule BnestApp.Deployment do
  @moduledoc false

  @type health :: %{status: String.t(), revision: String.t(), slot: String.t()}

  @spec revision() :: String.t()
  def revision, do: System.get_env("BNEST_RELEASE_REVISION", "development")

  @spec slot() :: String.t()
  def slot, do: System.get_env("BNEST_DEPLOY_SLOT", "standalone")

  @spec liveness() :: {:ok, health()}
  def liveness, do: {:ok, %{status: "live", revision: revision(), slot: slot()}}

  @spec readiness() :: {:ok, health()} | {:error, atom()}
  def readiness do
    with :ok <- running?(BnestApp.DataRepository),
         :ok <- running?(BnestApp.Identity),
         :ok <- running?(BnestApp.Codex.ModelCatalog),
         :ok <- peer_ready?() do
      {:ok, %{status: "ready", revision: revision(), slot: slot()}}
    end
  end

  defp running?(name), do: if(Process.whereis(name), do: :ok, else: {:error, :not_ready})

  defp peer_ready? do
    case System.get_env("BNEST_DEPLOY_PEER") do
      nil ->
        :ok

      "" ->
        :ok

      peer ->
        if Node.alive?() and Node.ping(String.to_atom(peer)) == :pong do
          :ok
        else
          {:error, :peer_unavailable}
        end
    end
  end
end
