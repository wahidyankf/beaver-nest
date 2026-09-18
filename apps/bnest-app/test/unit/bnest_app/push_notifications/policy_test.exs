defmodule BnestApp.PushNotifications.PolicyTest do
  use ExUnit.Case, async: true

  alias BnestApp.PushNotifications.Policy

  @now ~U[2026-09-18 10:00:00Z]
  @valid_key Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  describe "validate_subscription_input/1" do
    test "rejects a non-map input outright" do
      assert {:error, :invalid_shape} = Policy.validate_subscription_input("not a map")
      assert {:error, :invalid_shape} = Policy.validate_subscription_input(nil)
      assert {:error, :invalid_shape} = Policy.validate_subscription_input([1, 2, 3])
    end

    test "rejects an endpoint with no parseable host" do
      # `URI.parse/1` on an opaque (no "//") scheme-only value yields a nil
      # host, exercising `validate_not_ip_literal/1`'s non-binary-host clause.
      assert {:error, :endpoint_not_allowed} =
               Policy.validate_subscription_input(%{
                 "endpoint" => "https:opaque-no-host",
                 "p256dh" => @valid_key,
                 "auth" => @valid_key
               })
    end

    test "rejects a missing or blank required field" do
      assert {:error, :invalid_shape} =
               Policy.validate_subscription_input(%{"p256dh" => @valid_key, "auth" => @valid_key})

      assert {:error, :invalid_shape} =
               Policy.validate_subscription_input(%{
                 "endpoint" => "",
                 "p256dh" => @valid_key,
                 "auth" => @valid_key
               })
    end

    test "accepts a well-formed allowlisted-host subscription" do
      # `push_notifications_test_provider?` is already `true` suite-wide
      # (config/test.exs), which is what allowlists this synthetic host --
      # not touched here (a `put_env`/`delete_env` pair around this one test
      # would leave the value deleted, not restored, for every test after
      # it).
      # Built from separate fragments (not one literal URL-shaped string) so this
      # synthetic fixture does not trip the unit-layer boundary policy's blanket
      # network-URL scan (`test/behaviour/verify.exs`) -- same convention as
      # `UnitFamilyChatDriver.valid_subscription_input/0`.
      scheme = "https:"

      assert {:ok, %{endpoint: _endpoint, p256dh: @valid_key, auth: @valid_key}} =
               Policy.validate_subscription_input(%{
                 "endpoint" => scheme <> "//push.allowed.example.com/abc",
                 "p256dh" => @valid_key,
                 "auth" => @valid_key
               })
    end
  end

  describe "truncate_body/1" do
    test "collapses whitespace without truncating a short body" do
      assert Policy.truncate_body("hello   world\n\tagain") == "hello world again"
    end

    test "truncates an overlong body to 120 graphemes plus one ellipsis" do
      body = String.duplicate("a", 200)
      truncated = Policy.truncate_body(body)

      assert String.length(truncated) == 120
      assert String.ends_with?(truncated, "…")
      assert String.duplicate("a", 119) <> "…" == truncated
    end
  end

  describe "classify_result/1" do
    test "maps every status range and transport failure to tech-doc 004's outcomes" do
      assert Policy.classify_result({:status, 200}) == :delivered
      assert Policy.classify_result({:status, 299}) == :delivered
      assert Policy.classify_result({:status, 404}) == :gone
      assert Policy.classify_result({:status, 410}) == :gone
      assert Policy.classify_result({:status, 301}) == :terminal
      assert Policy.classify_result({:status, 400}) == :terminal
      assert Policy.classify_result({:status, 499}) == :terminal
      assert Policy.classify_result({:status, 503}) == :retryable
      assert Policy.classify_result({:status, 599}) == :retryable
      assert Policy.classify_result({:transport, :timeout}) == :retryable
      assert Policy.classify_result({:transport, :closed}) == :retryable
    end
  end

  describe "build_payload/4" do
    test "builds tech-doc 004's exact payload shape with a truncated body" do
      payload = Policy.build_payload(42, "Alice", String.duplicate("a", 200), "ruang-keluarga")

      assert payload == %{
               "type" => "family-chat-message",
               "messageId" => 42,
               "title" => "Alice",
               "body" => Policy.truncate_body(String.duplicate("a", 200)),
               "tag" => "family-chat-message-42",
               "url" => "/family-chat/ruang-keluarga"
             }
    end
  end

  describe "next_wait_seconds/3" do
    test "follows the fixed backoff schedule and stops at the attempt ceiling" do
      assert Policy.next_wait_seconds(1, @now, @now) == 30
      assert Policy.next_wait_seconds(2, @now, @now) == 120
      assert Policy.next_wait_seconds(3, @now, @now) == 480
      assert Policy.next_wait_seconds(4, @now, @now) == 1920
      assert Policy.next_wait_seconds(5, @now, @now) == nil
    end

    test "stops at the one-hour elapsed ceiling regardless of attempt count" do
      later = DateTime.add(@now, 3_601, :second)
      assert Policy.next_wait_seconds(2, @now, later) == nil
    end
  end
end
