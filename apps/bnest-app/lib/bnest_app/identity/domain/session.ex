defmodule BnestApp.Identity.Domain.Session do
  @moduledoc """
  Browser-session records. A session is stored under the SHA-256 digest of its token, never
  the token itself, and it has no expiry: it lives until it is revoked.
  """

  @doc "The lowercase hex SHA-256 digest a session is stored and announced under."
  @spec digest(String.t()) :: String.t()
  def digest(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  @doc "A live session record for `user_id`, issued at `now`."
  @spec new(String.t(), String.t(), String.t()) :: map()
  def new(token_digest, user_id, now) do
    %{
      "schemaVersion" => 1,
      "recordType" => "browser-session",
      "tokenDigest" => token_digest,
      "userId" => user_id,
      "issuedAt" => now,
      "revokedAt" => nil
    }
  end

  @doc "`session` revoked at `now`."
  @spec revoke(map(), String.t()) :: map()
  def revoke(session, now), do: Map.put(session, "revokedAt", now)

  @doc "The account fields a signed-in caller may see: never the password verifier."
  @spec public_account(map()) :: map()
  def public_account(account),
    do: Map.take(account, ~w(userId displayUsername normalizedUsername roles))
end
