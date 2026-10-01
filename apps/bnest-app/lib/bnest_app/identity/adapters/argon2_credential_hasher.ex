defmodule BnestApp.Identity.Adapters.Argon2CredentialHasher do
  @moduledoc """
  The `BnestApp.Identity.Ports.CredentialHasher` over Argon2id, with the work factor that
  `config :argon2_elixir` sets. It is the only Identity module that calls `Argon2`.
  """

  @behaviour BnestApp.Identity.Ports.CredentialHasher

  @impl true
  @spec hash(String.t()) :: {:ok, String.t()}
  def hash(password), do: {:ok, Argon2.hash_pwd_salt(password)}

  @impl true
  @spec verify(term(), term()) :: boolean()
  def verify(password, verifier) when is_binary(password) and is_binary(verifier) do
    Argon2.verify_pass(password, verifier)
  rescue
    _invalid_verifier -> false
  end

  def verify(_password, _verifier), do: false

  @impl true
  @spec no_user_verify() :: false
  def no_user_verify, do: Argon2.no_user_verify()

  @impl true
  @spec benchmark() :: {:ok, non_neg_integer()} | {:error, :not_argon2id}
  def benchmark do
    started = System.monotonic_time()
    verifier = Argon2.hash_pwd_salt(:crypto.strong_rand_bytes(32))

    elapsed_ms =
      System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)

    if String.starts_with?(verifier, "$argon2id$"),
      do: {:ok, elapsed_ms},
      else: {:error, :not_argon2id}
  end
end
