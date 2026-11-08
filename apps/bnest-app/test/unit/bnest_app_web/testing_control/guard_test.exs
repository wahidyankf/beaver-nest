defmodule BnestAppWeb.TestingControl.GuardTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.TestingControl.Guard

  # Synthetic values only. The decision is a pure function of the peer, the headers, the secret,
  # the runtime's ownership and the instance id in the path.
  @secret String.duplicate("s", 32)
  @instance_id "0123456789abcdef"
  @forwarding_headers ~w(x-forwarded-for x-forwarded-host x-forwarded-proto forwarded x-real-ip)

  defp request(overrides \\ %{}) do
    Map.merge(
      %{
        remote_ip: {127, 0, 0, 1},
        headers: [{"x-bnest-testing", @secret}],
        secret: @secret,
        runtime_owned?: true,
        instance_id: @instance_id
      },
      overrides
    )
  end

  test "admits a loopback request with the secret on an owned runtime" do
    assert Guard.decide(request()) == :ok
  end

  test "admits the IPv6 loopback peer" do
    assert Guard.decide(request(%{remote_ip: {0, 0, 0, 0, 0, 0, 0, 1}})) == :ok
  end

  test "a route without an id has no id to check" do
    assert Guard.decide(request(%{instance_id: nil})) == :ok
  end

  test "refuses every peer that is not 127.0.0.1 or ::1" do
    peers = [
      {10, 0, 0, 5},
      {192, 168, 1, 10},
      {127, 0, 0, 2},
      {0, 0, 0, 0, 0, 0, 0, 2},
      # An IPv4-mapped IPv6 address of the IPv4 loopback is not the loopback peer this model names.
      {0, 0, 0, 0, 0, 65_535, 32_512, 1}
    ]

    for peer <- peers do
      assert Guard.decide(request(%{remote_ip: peer})) == {:error, :not_loopback}
    end
  end

  test "refuses a request that came through a proxy, whatever its peer, with the secret right" do
    for name <- @forwarding_headers do
      headers = [{name, "203.0.113.7"}, {"x-bnest-testing", @secret}]

      assert Guard.decide(request(%{headers: headers})) == {:error, :forwarded},
             "#{name} must refuse the request"
    end
  end

  test "a forwarding header counts even with an empty value" do
    headers = [{"x-forwarded-proto", ""}, {"x-bnest-testing", @secret}]

    assert Guard.decide(request(%{headers: headers})) == {:error, :forwarded}
  end

  test "refuses a runtime the test run does not own, before it reads the secret" do
    assert Guard.decide(request(%{runtime_owned?: false, headers: []})) ==
             {:error, :runtime_not_owned}
  end

  test "refuses a wrong, missing, repeated or unset secret on a loopback request" do
    assert Guard.decide(request(%{headers: [{"x-bnest-testing", "wrong"}]})) ==
             {:error, :header_mismatch}

    assert Guard.decide(request(%{headers: []})) == {:error, :header_missing}

    assert Guard.decide(
             request(%{headers: [{"x-bnest-testing", @secret}, {"x-bnest-testing", @secret}]})
           ) ==
             {:error, :header_repeated}

    assert Guard.decide(request(%{secret: nil})) == {:error, :secret_unset}
    assert Guard.decide(request(%{secret: "short"})) == {:error, :secret_short}
  end

  test "judges the peer before the secret" do
    assert Guard.decide(request(%{remote_ip: {10, 0, 0, 5}, secret: nil})) ==
             {:error, :not_loopback}
  end

  test "refuses an instance id that does not match the lowercase sixteen-character form" do
    bad_ids = [
      "0123456789ABCDEF",
      "0123456789abcde",
      "0123456789abcdef0",
      "0123456789abcde-",
      "0123456789abcdef\n",
      "../../../etc/passwd"
    ]

    for id <- bad_ids do
      assert Guard.decide(request(%{instance_id: id})) == {:error, :bad_instance_id},
             "#{inspect(id)} must be refused"
    end
  end

  test "the plug turns a refusal into the missing-route error, and never reads the secret into it" do
    conn = Plug.Test.conn(:post, "/__bnest_testing/v1/instances")

    error =
      assert_raise Phoenix.Router.NoRouteError, fn ->
        Guard.call(conn, Guard.init([]))
      end

    assert error.conn.method == "POST"
    refute error.message =~ @secret
  end

  test "an unowned runtime is what the plug reads when no integration run configured the app" do
    refute Guard.runtime_owned?()
  end

  test "admit lets an admitted request through, and a refusal raises the missing-route error" do
    conn = Plug.Test.conn(:get, "/__bnest_testing/v1/state")

    assert Guard.admit(conn, :ok) == conn

    error =
      assert_raise Phoenix.Router.NoRouteError, fn ->
        Guard.admit(conn, {:error, :header_missing})
      end

    assert error.conn.method == "GET"
  end

  test "two root validations own the runtime only when both are ok and name the same run" do
    assert Guard.same_run?({:ok, %{run_id: "run-1"}}, {:ok, %{run_id: "run-1"}})
    refute Guard.same_run?({:ok, %{run_id: "run-1"}}, {:ok, %{run_id: "run-2"}})
    refute Guard.same_run?(:ok, {:ok, %{run_id: "run-1"}})
    refute Guard.same_run?({:error, :symlink}, {:error, :symlink})
  end

  test "no runtime is owned unless the flag is set and both roots are paths" do
    refute Guard.owned_by?(false, "/nonexistent/flat", "/nonexistent/sqlite")
    refute Guard.owned_by?(true, nil, "/nonexistent/sqlite")
    refute Guard.owned_by?(true, "/nonexistent/flat", nil)
  end

  test "roots outside the test run directories never count as owned" do
    refute Guard.owned_by?(true, "/nonexistent/flat", "/nonexistent/sqlite")
  end
end
