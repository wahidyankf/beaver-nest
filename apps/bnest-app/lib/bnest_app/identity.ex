defmodule BnestApp.Identity do
  @moduledoc false

  use GenServer

  alias BnestApp.DataRepository
  alias BnestApp.Identity.Authorization
  alias BnestApp.Identity.Bootstrap
  alias BnestApp.Identity.FileStore
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

  # Tech-doc 002: "Logout completes server deactivation before identity
  # revocation. If deactivation fails, the authenticated session remains so
  # the user can retry; partial logout is not reported as success." A raised
  # error from `PushNotifications.disable_subscription/2` (e.g. an
  # unavailable database) propagates out of this function before
  # `Login.revoke/3` ever runs, so the session cookie/file stays valid for a
  # retry rather than being revoked ahead of a failed deactivation.
  def logout(token) do
    with {:ok, %{"userId" => user_id}} <- Session.current_user(active_store(), token) do
      BnestApp.PushNotifications.disable_subscription(user_id, Session.digest(token))
    end

    Login.revoke(active_store(), token, BnestAppWeb.Endpoint)
  end

  def authorize(user, capability, owner_id), do: Authorization.allow?(user, capability, owner_id)

  # The current account's real display name, for callers (family chat message
  # reads) that must reflect the sender as they stand *now* rather than the
  # value stamped into a historical record at write time. `nil` when no
  # account exists (a deleted user, or a non-account sender like a system
  # producer) -- callers fall back to their own stored/historical value.
  @spec display_name_for(String.t()) :: String.t() | nil
  def display_name_for(user_id) do
    case FileStore.read_account(active_store(), user_id) do
      {:ok, %{"displayUsername" => display}} -> display
      _not_found -> nil
    end
  end

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
