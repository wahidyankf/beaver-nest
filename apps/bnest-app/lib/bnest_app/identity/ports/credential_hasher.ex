defmodule BnestApp.Identity.Ports.CredentialHasher do
  @moduledoc """
  Turns a password into a salted verifier and checks a password against one. The password
  rules live in `BnestApp.Identity.Domain.Credentials`; the application checks them before
  it hashes, so an implementation hashes whatever it is given.

  `no_user_verify/0` spends the cost of one verification without a verifier, so a login
  for an unknown username takes as long as one with a wrong password.
  """

  @callback hash(password :: String.t()) :: {:ok, String.t()} | {:error, atom()}
  @callback verify(password :: term(), verifier :: term()) :: boolean()
  @callback no_user_verify() :: false

  @doc """
  Hashes a random password once with the configured work factor. Returns the elapsed
  milliseconds, or `{:error, :not_argon2id}` when the verifier is not Argon2id.
  """
  @callback benchmark() :: {:ok, non_neg_integer()} | {:error, atom()}

  @optional_callbacks benchmark: 0
end
