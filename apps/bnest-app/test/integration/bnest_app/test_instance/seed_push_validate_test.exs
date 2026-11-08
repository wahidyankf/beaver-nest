defmodule BnestApp.TestInstance.SeedPushValidateTest do
  # The push-subscription checks of `BnestApp.TestInstance.Seed.validate/2` (ADR 001, section 2). They
  # take endpoint URLs, which the unit boundary policy refuses in unit test source, so they live in the
  # integration layer. `validate/2` is pure: nothing here touches a database, a socket or a process.
  # Every name, key and endpoint is synthetic.
  use ExUnit.Case, async: true

  @moduletag :test_instance

  alias BnestApp.TestInstance.Seed

  # The instance short id is the first eight characters of its id.
  @instance %{instance_id: "a1b2c3d4e5f6g7h8"}
  @admin "test-user-a1b2c3d4-admin"
  @parent "test-user-a1b2c3d4-parent"
  @password "Synthetic!Pass1"
  @endpoint "https://push.allowed.example.com/sub-1"

  defp account(name, roles \\ ["parents"]),
    do: %{"username" => name, "password" => @password, "roles" => roles}

  defp subscription(owner, endpoint \\ @endpoint),
    do: %{"owner" => owner, "endpoint" => endpoint, "p256dh" => "AAAA", "auth" => "AAAA"}

  defp seeded(usernames) do
    Map.put(
      @instance,
      :seeded,
      Map.new(usernames, &{&1, %{user_id: "user-" <> &1, roles: ["parents"]}})
    )
  end

  defp rejected(seed, instance \\ @instance) do
    assert {:error, %{code: :seed_invalid} = error} = Seed.validate(seed, instance)
    error
  end

  describe "validate/2 accepts a push subscription" do
    test "normalizes a push subscription to its owner, endpoint and keys" do
      seed = %{"accounts" => [account(@parent)], "pushSubscriptions" => [subscription(@parent)]}

      assert {:ok, normalized} = Seed.validate(seed, @instance)

      assert normalized["pushSubscriptions"] == [
               %{
                 "owner" => @parent,
                 "endpoint" => @endpoint,
                 "p256dh" => "AAAA",
                 "auth" => "AAAA"
               }
             ]
    end

    test "accepts a push owner that an earlier seed created" do
      assert {:ok, _seed} =
               Seed.validate(%{"pushSubscriptions" => [subscription(@admin)]}, seeded([@admin]))
    end

    test "a push endpoint on a production push service is accepted" do
      seed = %{"pushSubscriptions" => [subscription(@parent, "https://web.push.apple.com/abc")]}

      assert {:ok, _seed} = Seed.validate(seed, seeded([@parent]))
    end
  end

  describe "unknown_owner and too_many" do
    test "a push owner that is not seeded is unknown_owner" do
      assert %{reason: :unknown_owner, path: "pushSubscriptions[0].owner"} =
               rejected(%{"pushSubscriptions" => [subscription(@parent)]})
    end

    test "refuses 41 push subscriptions at pushSubscriptions" do
      subscriptions =
        for i <- 1..41, do: subscription(@parent, "https://push.allowed.example.com/sub-#{i}")

      assert %{reason: :too_many, path: "pushSubscriptions"} =
               rejected(%{"pushSubscriptions" => subscriptions}, seeded([@parent]))
    end
  end

  describe "invalid_payload at a push subscription" do
    test "a push endpoint that is not https is refused at its endpoint" do
      seed = %{
        "pushSubscriptions" => [subscription(@parent, "http://push.allowed.example.com/x")]
      }

      assert %{reason: :invalid_payload, path: "pushSubscriptions[0].endpoint"} =
               rejected(seed, seeded([@parent]))
    end

    test "a push endpoint whose host is not allowed is refused at its endpoint" do
      seed = %{"pushSubscriptions" => [subscription(@parent, "https://evil.example.org/x")]}

      assert %{reason: :invalid_payload, path: "pushSubscriptions[0].endpoint"} =
               rejected(seed, seeded([@parent]))
    end

    test "a push key that is not url-safe base64 is refused at that key" do
      seed = %{
        "pushSubscriptions" => [%{subscription(@parent) | "p256dh" => "not base64 !"}]
      }

      assert %{reason: :invalid_payload, path: "pushSubscriptions[0].p256dh"} =
               rejected(seed, seeded([@parent]))
    end

    test "a second subscription with the same endpoint is invalid_payload at its endpoint" do
      seed = %{"pushSubscriptions" => [subscription(@parent), subscription(@parent)]}

      assert %{reason: :invalid_payload, path: "pushSubscriptions[1].endpoint"} =
               rejected(seed, seeded([@parent]))
    end

    test "a push auth that is not unpadded base64url is invalid_payload at auth" do
      seed = %{
        "pushSubscriptions" => [
          Map.put(subscription(@parent), "auth", "not base64!")
        ]
      }

      assert %{reason: :invalid_payload, path: "pushSubscriptions[0].auth"} =
               rejected(seed, seeded([@parent]))
    end
  end

  describe "errors never echo a push secret" do
    test "a refused push key or endpoint is not in the error" do
      secret_key = "SECRETKEY probe"

      seed = %{
        "pushSubscriptions" => [
          %{
            "owner" => @parent,
            "endpoint" => "https://evil.example.org/SECRETPATH",
            "p256dh" => secret_key,
            "auth" => "AAAA"
          }
        ]
      }

      error = rejected(seed, seeded([@parent]))

      refute inspect(error) =~ "SECRETKEY"
      refute inspect(error) =~ "SECRETPATH"
    end
  end

  test "the push session key is a fixed prefix on the endpoint" do
    assert Seed.push_session_key(@endpoint) == "test-seed-push:" <> @endpoint
  end
end
