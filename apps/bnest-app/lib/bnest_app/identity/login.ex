defmodule BnestApp.Identity.Login do
  @moduledoc false

  # Credential and session-lifecycle logic, expressed against any store the identity
  # backend accepts. `BnestApp.Identity` is the adapter that decides which store is active;
  # this module never makes that decision, so it stays reachable without a runtime root.

  alias BnestApp.Identity.CredentialVerifier
  alias BnestApp.Identity.FileStore
  alias BnestApp.Identity.Session

  @spec authenticate(term(), term(), term()) :: {:ok, String.t()} | {:error, atom()}
  def authenticate(store, username, password) do
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

  @spec revoke(term(), term(), module()) :: :ok
  def revoke(store, token, notifier) do
    case Session.revoke(store, token) do
      {:ok, digest} ->
        notifier.broadcast("identity:#{digest}", "disconnect", %{})
        :ok

      {:error, :unauthenticated} ->
        :ok
    end
  end

  # A miss still pays the verifier cost, so a caller cannot distinguish an unknown username
  # from a wrong password by timing.
  defp invalid_login do
    CredentialVerifier.no_user_verify()
    {:error, :invalid_credentials}
  end
end
