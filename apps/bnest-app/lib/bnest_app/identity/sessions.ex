defmodule BnestApp.Identity.Sessions do
  @moduledoc """
  The browser-session lifecycle against an identity store: issue a random token, resolve a
  token to its account, and revoke it. The caller keeps the token; the store keeps only its
  digest.
  """

  alias BnestApp.Identity.Domain.Session
  alias BnestApp.Identity.Ports.IdentityStore

  @spec create(IdentityStore.handle(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def create(store, user_id), do: create(store, user_id, 3)

  @spec current_user(IdentityStore.handle(), String.t()) ::
          {:ok, map()} | {:error, :unauthenticated}
  def current_user(store, token) when is_binary(token) do
    with {:ok, %{"userId" => user_id, "revokedAt" => nil}} <-
           IdentityStore.read_session(store, Session.digest(token)),
         {:ok, account} <- IdentityStore.read_account(store, user_id) do
      {:ok, Session.public_account(account)}
    else
      _failure -> {:error, :unauthenticated}
    end
  end

  def current_user(_store, _token), do: {:error, :unauthenticated}

  @spec revoke(IdentityStore.handle(), String.t()) ::
          {:ok, String.t()} | {:error, :unauthenticated}
  def revoke(store, token) when is_binary(token) do
    digest = Session.digest(token)

    with {:ok, %{"revokedAt" => nil} = session} <- IdentityStore.read_session(store, digest),
         revoked = Session.revoke(session, timestamp()),
         {:ok, ^revoked} <- IdentityStore.replace_session(store, revoked) do
      {:ok, digest}
    else
      _failure -> {:error, :unauthenticated}
    end
  end

  def revoke(_store, _token), do: {:error, :unauthenticated}

  defp create(_store, _user_id, 0), do: {:error, :session_write_failed}

  # A digest collision with an existing session retries with a fresh token.
  defp create(store, user_id, attempts) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    record = Session.new(Session.digest(token), user_id, timestamp())

    case IdentityStore.put_session(store, record) do
      {:ok, ^record} -> {:ok, token}
      {:error, :exists} -> create(store, user_id, attempts - 1)
      {:error, _reason} -> {:error, :session_write_failed}
    end
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
