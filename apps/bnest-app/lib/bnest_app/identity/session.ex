defmodule BnestApp.Identity.Session do
  @moduledoc false

  alias BnestApp.Identity.FileStore

  @spec create(map(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def create(store, user_id), do: create(store, user_id, 3)

  @spec current_user(map(), String.t()) :: {:ok, map()} | {:error, :unauthenticated}
  def current_user(store, token) when is_binary(token) do
    digest = digest(token)

    with {:ok, %{"userId" => user_id, "revokedAt" => nil}} <-
           FileStore.read_session(store, digest),
         {:ok, account} <- FileStore.read_account(store, user_id) do
      {:ok, public_account(account)}
    else
      _failure -> {:error, :unauthenticated}
    end
  end

  def current_user(_store, _token), do: {:error, :unauthenticated}

  @spec revoke(map(), String.t()) :: {:ok, String.t()} | {:error, :unauthenticated}
  def revoke(store, token) when is_binary(token) do
    digest = digest(token)

    with {:ok, %{"revokedAt" => nil} = session} <- FileStore.read_session(store, digest),
         revoked = Map.put(session, "revokedAt", timestamp()),
         {:ok, ^revoked} <- FileStore.replace_session(store, revoked) do
      {:ok, digest}
    else
      _failure -> {:error, :unauthenticated}
    end
  end

  def revoke(_store, _token), do: {:error, :unauthenticated}

  @spec digest(String.t()) :: String.t()
  def digest(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  defp create(_store, _user_id, 0), do: {:error, :session_write_failed}

  defp create(store, user_id, attempts) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    token_digest = digest(token)

    record = %{
      "schemaVersion" => 1,
      "recordType" => "browser-session",
      "tokenDigest" => token_digest,
      "userId" => user_id,
      "issuedAt" => timestamp(),
      "revokedAt" => nil
    }

    case FileStore.put_session(store, record) do
      {:ok, ^record} -> {:ok, token}
      {:error, :exists} -> create(store, user_id, attempts - 1)
      {:error, _reason} -> {:error, :session_write_failed}
    end
  end

  defp public_account(account),
    do: Map.take(account, ~w(userId displayUsername normalizedUsername roles))

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
