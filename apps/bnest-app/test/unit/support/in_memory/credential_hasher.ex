defmodule BnestApp.Test.InMemory.CredentialHasher do
  @moduledoc """
  A deterministic `BnestApp.Identity.Ports.CredentialHasher` for the unit layer. Its verifier
  is a SHA-256 digest of a fixed salt and the password, so it never holds the plaintext, but
  it is no password hash: only the Argon2id adapter is, and the integration layer proves it.
  """

  @behaviour BnestApp.Identity.Ports.CredentialHasher

  @prefix "$in-memory$"

  @impl true
  def hash(password) when is_binary(password), do: {:ok, @prefix <> digest(password)}

  @impl true
  def verify(password, @prefix <> expected) when is_binary(password),
    do: digest(password) == expected

  def verify(_password, _verifier), do: false

  @impl true
  def no_user_verify, do: false

  @impl true
  def benchmark, do: {:ok, 0}

  defp digest(password),
    do: :crypto.hash(:sha256, "test-user-salt:" <> password) |> Base.encode16(case: :lower)
end
