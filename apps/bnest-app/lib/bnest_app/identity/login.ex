defmodule BnestApp.Identity.Login do
  @moduledoc """
  Credential checks and logout, expressed against any identity store handle. The facade
  decides which store is active; this module never makes that decision, so a test can run
  it against an in-memory store. The credential hasher and the session notifier come from
  the facade's configuration.
  """

  alias BnestApp.Identity
  alias BnestApp.Identity.Domain.Credentials
  alias BnestApp.Identity.Ports.IdentityStore
  alias BnestApp.Identity.Sessions

  @spec authenticate(IdentityStore.handle(), term(), term()) ::
          {:ok, String.t()} | {:error, atom()}
  def authenticate(store, username, password) do
    hasher = Identity.adapter(:credential_hasher)

    with {:ok, {_display, normalized}} <- Credentials.normalize_username(username),
         {:ok, %{"userId" => user_id}} <- IdentityStore.read_username(store, normalized),
         {:ok, account} <- IdentityStore.read_account(store, user_id),
         true <- hasher.verify(password, account["passwordVerifier"]),
         {:ok, token} <- Sessions.create(store, user_id) do
      {:ok, token}
    else
      {:error, :missing} -> invalid_login(hasher)
      false -> {:error, :invalid_credentials}
      _failure -> {:error, :invalid_credentials}
    end
  end

  @doc "Revokes the session and disconnects its live connections. Idempotent."
  @spec revoke(IdentityStore.handle(), term()) :: :ok
  def revoke(store, token) do
    case Sessions.revoke(store, token) do
      {:ok, digest} ->
        Identity.adapter(:session_notifier).disconnect(digest)
        :ok

      {:error, :unauthenticated} ->
        :ok
    end
  end

  # A miss still pays the verifier cost, so a caller cannot distinguish an unknown username
  # from a wrong password by timing.
  defp invalid_login(hasher) do
    hasher.no_user_verify()
    {:error, :invalid_credentials}
  end
end
