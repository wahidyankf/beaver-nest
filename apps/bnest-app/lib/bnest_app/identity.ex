defmodule BnestApp.Identity do
  @moduledoc false

  use GenServer

  alias BnestApp.DataRepository
  alias BnestApp.Identity.Authorization
  alias BnestApp.Identity.Bootstrap
  alias BnestApp.Identity.Login
  alias BnestApp.Identity.Session
  alias BnestApp.Storage.Config, as: StorageConfig

  def start_link(options) do
    case Keyword.get(options, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, options)
      name -> GenServer.start_link(__MODULE__, options, name: name)
    end
  end

  def bootstrap(accounts, server \\ __MODULE__),
    do: GenServer.call(server, {:bootstrap, accounts}, :infinity)

  def setup_status(server \\ __MODULE__), do: GenServer.call(server, :setup_status)

  def login(username, password), do: Login.authenticate(active_store(), username, password)
  def current_user(token), do: Session.current_user(active_store(), token)
  def logout(token), do: Login.revoke(active_store(), token, BnestAppWeb.Endpoint)

  def authorize(user, capability, owner_id), do: Authorization.allow?(user, capability, owner_id)

  @impl GenServer
  def init(options) do
    source =
      case Keyword.fetch(options, :store) do
        {:ok, store} -> {:fixed, store}
        :error -> :active
      end

    case Bootstrap.recover(resolve_store(source)) do
      :ok -> {:ok, %{source: source}}
      {:error, reason} -> {:stop, {:identity_recovery_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:bootstrap, accounts}, _from, state),
    do: {:reply, Bootstrap.create(resolve_store(state.source), accounts), state}

  def handle_call(:setup_status, _from, state),
    do: {:reply, Bootstrap.status(resolve_store(state.source)), state}

  defp resolve_store({:fixed, store}), do: store
  defp resolve_store(:active), do: active_store()

  defp active_store do
    case StorageConfig.phase() do
      :sqlite_primary -> DataRepository
      :flat_primary -> DataRepository.store()
    end
  end
end
