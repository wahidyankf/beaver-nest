defmodule BnestAppWeb.TestingControl.LogFilterTest do
  use ExUnit.Case, async: true

  # Phoenix prints request parameters at debug level. The test config filters every parameter whose
  # key holds one of these words, so a push key, an auth key, a password or a secret never reaches a
  # log line. Nothing else is filtered: an endpoint or a seed key stays readable.
  @secret_keys ~w(p256dh auth password secret)

  test "the test config lists each credential word as a filtered parameter" do
    configured = Application.get_env(:phoenix, :filter_parameters, [])

    for key <- @secret_keys do
      assert key in configured, "#{key} must be in :filter_parameters"
    end
  end

  test "a parameter holding a credential is printed as FILTERED, and a plain one is kept" do
    filter = Application.get_env(:phoenix, :filter_parameters, [])

    params = %{
      "p256dh" => "BPublicKey",
      "auth" => "AuthSecret",
      "password" => "Synthetic!Pass1",
      "endpoint" => "https://push.allowed.example.com/one",
      "seedKey" => "admins"
    }

    filtered = Phoenix.Logger.filter_values(params, filter)

    assert filtered["p256dh"] == "[FILTERED]"
    assert filtered["auth"] == "[FILTERED]"
    assert filtered["password"] == "[FILTERED]"
    assert filtered["endpoint"] == "https://push.allowed.example.com/one"
    assert filtered["seedKey"] == "admins"
  end
end
