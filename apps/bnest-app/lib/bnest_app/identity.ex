defmodule BnestApp.Identity do
  @moduledoc false

  use GenServer

  alias BnestApp.DataRepository
  alias BnestApp.Identity.Authorization
  alias BnestApp.Identity.Bootstrap
  alias BnestApp.Identity.CredentialVerifier
  alias BnestApp.Identity.FileStore
  alias BnestApp.Identity.Session
  alias BnestApp.Storage.Config, as: StorageConfig

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)
  def bootstrap(accounts), do: GenServer.call(__MODULE__, {:bootstrap, accounts}, :infinity)
  def setup_status, do: GenServer.call(__MODULE__, :setup_status)

  def login(username, password), do: login(active_store(), username, password)
  def current_user(token), do: Session.current_user(active_store(), token)

  def logout(token) do
    case Session.revoke(active_store(), token) do
      {:ok, digest} ->
        BnestAppWeb.Endpoint.broadcast("identity:#{digest}", "disconnect", %{})
        :ok

      {:error, :unauthenticated} ->
        :ok
    end
  end

  def authorize(user, capability, owner_id), do: Authorization.allow?(user, capability, owner_id)

  @impl GenServer
  def init(options) do
    source =
      case Keyword.fetch(options, :store) do
        {:ok, store} -> {:fixed, store}
        :error -> :active
      end

    case Bootstrap.recover(resolve_store(source)) do
      :ok -> {:ok, source}
      {:error, reason} -> {:stop, {:identity_recovery_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:bootstrap, accounts}, _from, source),
    do: {:reply, Bootstrap.create(resolve_store(source), accounts), source}

  def handle_call(:setup_status, _from, source),
    do: {:reply, Bootstrap.status(resolve_store(source)), source}

  defp login(store, username, password) do
    with {:ok, {_display, normalized}} <- FileStore.normalize_username(username),
         {:ok, %{"userId" => user_id}} <- FileStore.read_username(store, normalized),
         {:ok, account} <- FileStore.read_account(store, user_id),
         true <- CredentialVerifier.verify(password, account["passwordVerifier"]),
         {:ok, token} <- Session.create(store, user_id) do
      {:ok, token}
    else
      {:error, :missing} -> invalid_login()
      false -> {:error, :invalid_credentials}
      _failure -> {:error, :invalid_credentials}
    end
  end

  defp invalid_login do
    CredentialVerifier.no_user_verify()
    {:error, :invalid_credentials}
  end

  defp resolve_store({:fixed, store}), do: store
  defp resolve_store(:active), do: active_store()

  defp active_store do
    case StorageConfig.phase() do
      :sqlite_primary -> DataRepository
      :flat_primary -> DataRepository.store()
    end
  end
end
