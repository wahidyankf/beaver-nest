defmodule BnestApp.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias BnestApp.DataRepository.Store

  @impl true
  def start(_type, _args) do
    children =
      [
        BnestAppWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:bnest_app, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: BnestApp.PubSub},
        BnestApp.Codex.ModelCatalog
      ] ++
        repository_children() ++
        [
          BnestAppWeb.Endpoint,
          # `familyChatMessageCommitted` subscriptions. Fixed pool size per
          # tech-doc 008 — never derived from system core count, so behavior
          # is identical across dev/test/prod. Must start after the Endpoint
          # (it registers against the endpoint's pubsub) and unconditionally
          # (GraphQL subscriptions work even when `repository_children/0`
          # returns `[]`).
          {Absinthe.Subscription, pubsub: BnestAppWeb.Endpoint, pool_size: 8}
        ]

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
          {BnestApp.DataRepository, store: Store.new!(root)},
          BnestApp.Identity,
          {Task.Supervisor, name: BnestApp.Scheduler.Tasks},
          {BnestApp.Scheduler,
           automatic?: Application.get_env(:bnest_app, :scheduler_automatic?, true)}
        ]
    end
  end
end
