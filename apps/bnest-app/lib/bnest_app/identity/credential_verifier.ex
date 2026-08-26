defmodule BnestApp.Identity.CredentialVerifier do
  @moduledoc false

  @spec hash(String.t()) :: {:ok, String.t()} | {:error, :invalid_password}
  def hash(password) do
    if valid_password?(password),
      do: {:ok, Argon2.hash_pwd_salt(password)},
      else: {:error, :invalid_password}
  end

  @spec verify(String.t(), String.t()) :: boolean()
  def verify(password, verifier) when is_binary(password) and is_binary(verifier) do
    Argon2.verify_pass(password, verifier)
  rescue
    _invalid_verifier -> false
  end

  def verify(_password, _verifier), do: false

  @spec no_user_verify() :: false
  def no_user_verify, do: Argon2.no_user_verify()

  @spec valid_password?(term()) :: boolean()
  def valid_password?(password) when is_binary(password) do
    String.valid?(password) and
      password != "" and
      String.match?(password, ~r/\p{L}/u) and
      String.match?(password, ~r/\p{Nd}/u) and
      String.match?(password, ~r/[[:punct:]]/u)
  end

  def valid_password?(_password), do: false
end
