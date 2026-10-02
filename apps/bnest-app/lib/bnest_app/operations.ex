defmodule BnestApp.Operations do
  @moduledoc """
  The Operations bounded context: what the running release reports about itself, its
  liveness, readiness and health, its revision and deployment slot, and the admin settings
  panels each context declares.

  This module is the context's application-service facade. The health controller, the
  release-header plug and the admin settings pages call only this module. The release
  environment comes from `config :bnest_app, BnestApp.Operations` (`:release_environment`,
  an adapter of `BnestApp.Operations.Ports.ReleaseEnvironment`), so a test can supply an
  in-memory double; the panels are the pure `BnestApp.Operations.Domain.AdminPanels`.
  Health reads storage and the scheduler only through the `Storage` and `Scheduler`
  facades.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [BnestApp.Scheduler, BnestApp.Storage],
    exports: [{Ports, []}]

  alias BnestApp.Operations.Domain.AdminPanels
  alias BnestApp.Operations.Ports.ReleaseEnvironment
  alias BnestApp.Scheduler
  alias BnestApp.Storage

  # The processes a slot serves from, checked in this order before the peer.
  @readiness_processes [
    BnestApp.Storage.Records,
    BnestApp.Identity,
    BnestApp.CodexChat.ModelCatalog
  ]

  @backup_schedule_key "prod-sqlite-backup-daily"
  @backup_handler_key "prod_sqlite_backup"

  @type status :: %{status: String.t(), revision: String.t(), slot: String.t()}
  @type health :: %{
          status: String.t(),
          revision: String.t(),
          slot: String.t(),
          sqliteReady: boolean(),
          schedulerReady: boolean(),
          storageGeneration: String.t() | nil
        }

  @doc "The configured adapter for an Operations port: `:release_environment`."
  @spec adapter(atom()) :: module()
  def adapter(port), do: :bnest_app |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(port)

  @doc "The revision the deployment released, or `\"development\"` when it named none."
  @spec revision() :: String.t()
  def revision, do: revision(environment())

  @doc "The deployment slot this server runs in, or `\"standalone\"` when it names none."
  @spec slot() :: String.t()
  def slot, do: slot(environment())

  @spec liveness() :: {:ok, status()}
  def liveness do
    environment = environment()
    {:ok, %{status: "live", revision: revision(environment), slot: slot(environment)}}
  end

  @doc """
  Ready once the record repository, Identity and the Codex model catalog run, in that
  order, and then the deployment's peer slot, when it names one, answers.
  """
  @spec readiness() :: {:ok, status()} | {:error, :not_ready | :peer_unavailable}
  def readiness do
    environment = environment()

    with :ok <- processes_running(environment),
         :ok <- peer_ready(environment) do
      {:ok, %{status: "ready", revision: revision(environment), slot: slot(environment)}}
    end
  end

  @doc """
  Readiness plus the storage state. Once SQLite is authoritative, the database must start
  under the shared storage lease and hold the release-seeded backup schedule, and the
  scheduler must run. The SQLite phase is optional-timing and decoupled from ordinary
  releases (see `BnestApp.Storage.migrate/2`), so while flat files are authoritative storage
  is not checked.
  """
  @spec health() ::
          {:ok, health()}
          | {:error, :not_ready | :peer_unavailable | :sqlite_not_ready | :scheduler_not_ready}
  def health do
    with {:ok, status} <- readiness(),
         :ok <- storage_ready() do
      {:ok,
       status
       |> Map.put(:sqliteReady, sqlite_primary?())
       |> Map.put(:schedulerReady, Scheduler.ready?())
       |> Map.put(:storageGeneration, Storage.database_generation())}
    end
  end

  @doc "Every admin settings panel the contexts declare, in display order."
  @spec admin_panels() :: [AdminPanels.panel()]
  def admin_panels, do: AdminPanels.panels()

  @spec fetch_admin_panel(String.t()) :: {:ok, AdminPanels.panel()} | :error
  def fetch_admin_panel(key), do: AdminPanels.fetch(key)

  defp environment, do: adapter(:release_environment).new()

  defp revision(environment), do: ReleaseEnvironment.revision(environment) || "development"
  defp slot(environment), do: ReleaseEnvironment.slot(environment) || "standalone"

  defp processes_running(environment) do
    if Enum.all?(@readiness_processes, &ReleaseEnvironment.running?(environment, &1)),
      do: :ok,
      else: {:error, :not_ready}
  end

  defp peer_ready(environment) do
    case ReleaseEnvironment.peer(environment) do
      nil ->
        :ok

      "" ->
        :ok

      peer ->
        if ReleaseEnvironment.peer_reachable?(environment, peer),
          do: :ok,
          else: {:error, :peer_unavailable}
    end
  end

  defp storage_ready do
    if sqlite_primary?() do
      Storage.with_shared_lock(fn ->
        Storage.ensure_started!()
        backup_schedule_ready()
      end)
    else
      :ok
    end
  rescue
    _error -> {:error, :sqlite_not_ready}
  end

  defp backup_schedule_ready do
    case Scheduler.get_schedule(@backup_schedule_key) do
      %{handler_key: @backup_handler_key, expiration_kind: "never"} ->
        if Scheduler.ready?(), do: :ok, else: {:error, :scheduler_not_ready}

      _missing ->
        {:error, :sqlite_not_ready}
    end
  end

  defp sqlite_primary?, do: Storage.phase() == :sqlite_primary
end
