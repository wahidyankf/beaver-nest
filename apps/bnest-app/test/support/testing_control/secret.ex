defmodule BnestAppWeb.TestingControl.Secret do
  @moduledoc """
  The run secret the testing-control routes compare against (ADR 001, section 2, guard 4).

  `check/2` is pure: it takes the values a request presents in `x-bnest-testing` and the secret the
  environment holds, and it admits a request only when exactly one presented value equals a secret
  of at least 32 bytes. Every other input is refused, and the unset and short cases are judged
  before the header is looked at, so a missing secret closes every request.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @header "x-bnest-testing"
  @env "BNEST_TEST_CONTROL_SECRET"
  @minimum_bytes 32

  @spec header() :: String.t()
  def header, do: @header

  @doc "The environment variable the secret is read from, at request time."
  @spec env_name() :: String.t()
  def env_name, do: @env

  @spec minimum_bytes() :: pos_integer()
  def minimum_bytes, do: @minimum_bytes

  @spec check([String.t()], String.t() | nil) ::
          :ok
          | {:error,
             :secret_unset
             | :secret_short
             | :header_missing
             | :header_repeated
             | :header_mismatch}
  def check(_presented, nil), do: {:error, :secret_unset}

  def check(_presented, secret) when byte_size(secret) < @minimum_bytes,
    do: {:error, :secret_short}

  def check([], _secret), do: {:error, :header_missing}
  def check([_first, _second | _rest], _secret), do: {:error, :header_repeated}
  def check([value], secret), do: compare(value, secret)

  # The length is compared first, so the constant-time comparison only ever sees equal sizes.
  defp compare(value, secret) do
    if byte_size(value) == byte_size(secret) and Plug.Crypto.secure_compare(value, secret),
      do: :ok,
      else: {:error, :header_mismatch}
  end
end
