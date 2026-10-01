defmodule BnestApp.Identity do
  @moduledoc """
  The Identity bounded context: one-time account bootstrap, login, browser sessions, logout,
  and the authorization policy.

  This module is the context's application-service facade, and the process that recovers an
  interrupted bootstrap at start and serializes bootstrap calls. Its adapters come from
  application configuration under `config :bnest_app, BnestApp.Identity`, one per port in
  `BnestApp.Identity.Ports`, so a test can supply in-memory doubles. Unless a store handle
  is given at start, it works on the identity store over the record store Storage reports
  as active.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [BnestApp.Storage, Jason],
    exports: [{Domain, []}, {Ports, []}]

  use GenServer

  alias BnestApp.Identity.Bootstrap
  alias BnestApp.Identity.Domain.Authorization
  alias BnestApp.Identity.Domain.Session
  alias BnestApp.Identity.Login
  alias BnestApp.Identity.Ports.IdentityStore
  alias BnestApp.Identity.Sessions
  alias BnestApp.Storage

  @doc """
  The configured adapter for an Identity port: `:identity_store`, `:credential_hasher`,
  `:session_notifier` or `:subscription_revoker`.
  """
  @spec adapter(atom()) :: module()
  def adapter(port), do: :bnest_app |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(port)

  @doc """
  Starts the Identity process. `store:` fixes the identity store handle it works on;
  `name: nil` starts an unnamed instance.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    case Keyword.get(options, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, options)
      name -> GenServer.start_link(__MODULE__, options, name: name)
    end
  end

  def bootstrap(accounts, server \\ __MODULE__),
    do: GenServer.call(server, {:bootstrap, accounts}, :infinity)

  def setup_status(server \\ __MODULE__), do: GenServer.call(server, :setup_status)

  @spec login(term(), term()) :: {:ok, String.t()} | {:error, atom()}
  def login(username, password), do: Login.authenticate(active_store(), username, password)

  @spec current_user(term()) :: {:ok, map()} | {:error, :unauthenticated}
  def current_user(token), do: Sessions.current_user(active_store(), token)

  @doc """
  Ends the browser session of `token`: deactivates its push subscription, then revokes the
  session and disconnects its live connections. A failed deactivation raises before the
  session is revoked, so the user can retry. Idempotent for an unknown or revoked token.
  """
  @spec logout(term()) :: :ok
  def logout(token) do
    with {:ok, %{"userId" => user_id}} <- Sessions.current_user(active_store(), token) do
      adapter(:subscription_revoker).revoke(user_id, Session.digest(token))
    end

    Login.revoke(active_store(), token)
  end

  @spec authorize(map(), atom(), String.t() | nil) :: boolean()
  def authorize(user, capability, owner_id), do: Authorization.allow?(user, capability, owner_id)

  @doc """
  The public fields of the account `user_id` (never its password verifier), or
  `{:error, :missing}`.
  """
  @spec account(String.t()) :: {:ok, map()} | {:error, atom()}
  def account(user_id) do
    with {:ok, account} <- IdentityStore.read_account(active_store(), user_id),
         do: {:ok, Session.public_account(account)}
  end

  # The current account's real display name, for callers (family chat message
  # reads) that must reflect the sender as they stand *now* rather than the
  # value stamped into a historical record at write time. `nil` when no
  # account exists (a deleted user, or a non-account sender like a system
  # producer) -- callers fall back to their own stored/historical value.
  @spec display_name_for(String.t()) :: String.t() | nil
  def display_name_for(user_id) do
    case IdentityStore.read_account(active_store(), user_id) do
      {:ok, %{"displayUsername" => display}} -> display
      _not_found -> nil
    end
  end

  @doc "The digest a browser session is stored and announced under; never the token itself."
  @spec session_digest(String.t()) :: String.t()
  def session_digest(token), do: Session.digest(token)

  @doc "Times one hash with the configured credential hasher's work factor."
  @spec benchmark_hasher() :: {:ok, non_neg_integer()} | {:error, atom()}
  def benchmark_hasher, do: adapter(:credential_hasher).benchmark()

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

  defp active_store, do: adapter(:identity_store).new(Storage.active_store())
end
