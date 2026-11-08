defmodule BnestAppWeb.TestingControl.SecretTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.TestingControl.Secret

  # Synthetic: 32 bytes is the least secret the control accepts.
  @secret String.duplicate("s", 32)

  test "names the header and the environment variable the control reads" do
    assert Secret.header() == "x-bnest-testing"
    assert Secret.env_name() == "BNEST_TEST_CONTROL_SECRET"
    assert Secret.minimum_bytes() == 32
  end

  test "closes every request when the secret is unset, even with a matching header" do
    for presented <- [[], [@secret], ["anything"], [@secret, @secret]] do
      assert Secret.check(presented, nil) == {:error, :secret_unset}
    end
  end

  test "closes every request when the secret is shorter than 32 bytes" do
    short = String.duplicate("s", 31)

    assert Secret.check([short], short) == {:error, :secret_short}
    assert Secret.check([""], "") == {:error, :secret_short}
    assert Secret.check([], "") == {:error, :secret_short}
  end

  test "counts the minimum in bytes, not characters" do
    # Sixteen two-byte characters are 32 bytes, so the secret is long enough.
    thirty_two_bytes = String.duplicate("é", 16)
    assert Secret.check([thirty_two_bytes], thirty_two_bytes) == :ok

    # Fifteen of them are 30 bytes, which is too short whatever the header says.
    thirty_bytes = String.duplicate("é", 15)
    assert Secret.check([thirty_bytes], thirty_bytes) == {:error, :secret_short}
  end

  test "admits exactly one presented value equal to the secret" do
    assert Secret.check([@secret], @secret) == :ok
  end

  test "refuses a missing header" do
    assert Secret.check([], @secret) == {:error, :header_missing}
  end

  test "refuses a repeated header even when every value is right" do
    assert Secret.check([@secret, @secret], @secret) == {:error, :header_repeated}
  end

  test "refuses a wrong value of the same length" do
    wrong = String.duplicate("t", 32)

    assert Secret.check([wrong], @secret) == {:error, :header_mismatch}
  end

  test "refuses a value of another length, and a value that only extends the secret" do
    assert Secret.check(["x"], @secret) == {:error, :header_mismatch}
    assert Secret.check([@secret <> " "], @secret) == {:error, :header_mismatch}
    assert Secret.check([binary_part(@secret, 0, 31)], @secret) == {:error, :header_mismatch}
  end
end
