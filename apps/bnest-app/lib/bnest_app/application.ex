defmodule BnestApp.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        BnestAppWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:bnest_app, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: BnestApp.PubSub},
        BnestApp.Codex.ModelCatalog
      ] ++ repository_children() ++ [BnestAppWeb.Endpoint]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BnestApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BnestAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp repository_children do
    case Application.get_env(:bnest_app, :runtime_root) do
      nil ->
        []

      root ->
        [
          {BnestApp.DataRepository, root: root},
          BnestApp.Identity,
          {Task.Supervisor, name: BnestApp.Scheduler.Tasks},
          BnestApp.Scheduler
        ]
    end
  end
end
