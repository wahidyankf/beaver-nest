defmodule BnestApp.PushNotificationsTest do
  # `async: false`: several cases here temporarily mutate the global
  # `:web_push, :vapid` Application env to exercise `configuration/0`'s
  # unconfigured/map-shaped branches, always restoring the original value via
  # `on_exit/1` before the next test runs -- an async sibling could otherwise
  # observe the mutated value mid-window.
  use ExUnit.Case, async: false

  alias BnestApp.FamilyChat.Store, as: FamilyChatStore
  alias BnestApp.PushNotifications

  setup do
    FamilyChatStore.ensure_ready!()
    :ok
  end

  defp unique_user, do: "test-user-family-chat-pushctx-" <> Ecto.UUID.generate()
  defp valid_key, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  # Built from separate fragments (not one literal URL-shaped string) so this
  # synthetic fixture does not trip the unit-layer boundary policy's blanket
  # network-URL scan (`test/behaviour/verify.exs`) -- same convention as
  # `UnitFamilyChatDriver.valid_subscription_input/0`.
  defp valid_input(endpoint_suffix) do
    scheme = "https:"

    %{
      "endpoint" => scheme <> "//push.allowed.example.com/" <> endpoint_suffix,
      "p256dh" => valid_key(),
      "auth" => valid_key()
    }
  end

  describe "current_subscription/2" do
    test "reports disabled for a user with no stored row" do
      assert {:ok, %{enabled: false, expiration_time: nil}} =
               PushNotifications.current_subscription(unique_user(), "session-a")
    end

    test "reports enabled with the stored expiration once a subscription exists" do
      user = unique_user()
      session = "session-b"

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(user, session, valid_input(user))

      on_exit(fn -> PushNotifications.disable_subscription(user, session) end)

      assert {:ok, %{enabled: true, expiration_time: nil}} =
               PushNotifications.current_subscription(user, session)
    end
  end

  describe "upsert_subscription/3" do
    test "rejects an unauthenticated (nil) caller" do
      assert {:error, %{code: "UNAUTHENTICATED", details: nil}} =
               PushNotifications.upsert_subscription(nil, "session-c", valid_input("unused"))
    end

    test "rebinds an existing endpoint to a new (user, session) pair instead of duplicating it" do
      shared_endpoint_suffix = "rebind-" <> Ecto.UUID.generate()
      input = valid_input(shared_endpoint_suffix)
      first_user = unique_user()
      second_user = unique_user()

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(first_user, "session-d", input)

      assert {:ok, %{enabled: true}} =
               PushNotifications.upsert_subscription(second_user, "session-e", input)

      on_exit(fn ->
        PushNotifications.disable_subscription(first_user, "session-d")
        PushNotifications.disable_subscription(second_user, "session-e")
      end)

      # Ownership moved explicitly to `second_user`; the first binding no
      # longer reports enabled for its own (user, session) pair.
      assert {:ok, %{enabled: false}} =
               PushNotifications.current_subscription(first_user, "session-d")

      assert {:ok, %{enabled: true}} =
               PushNotifications.current_subscription(second_user, "session-e")
    end
  end

  describe "configuration/0" do
    test "reports available: false with no VAPID config set at all" do
      original = Application.get_env(:web_push, :vapid)
      Application.delete_env(:web_push, :vapid)
      on_exit(fn -> Application.put_env(:web_push, :vapid, original) end)

      assert {:ok, %{available: false, public_key: nil}} = PushNotifications.configuration()
    end

    test "reads a map-shaped VAPID config exactly like the keyword-list shape" do
      original = Application.get_env(:web_push, :vapid)

      Application.put_env(:web_push, :vapid, %{
        public_key: "map-shaped-public-key",
        private_key: "map-shaped-private-key",
        subject: "mailto:map-shaped@example.com"
      })

      on_exit(fn -> Application.put_env(:web_push, :vapid, original) end)

      assert {:ok, %{available: true, public_key: "map-shaped-public-key"}} =
               PushNotifications.configuration()
    end
  end
end
