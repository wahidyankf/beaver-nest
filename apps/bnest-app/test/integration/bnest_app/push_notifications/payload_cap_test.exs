defmodule BnestApp.PushNotifications.PayloadCapTest do
  # A real dispatch on a spawned instance sends the capped payload the
  # behaviour names: a long body arrives collapsed to 120 graphemes with one
  # ellipsis, a 120-grapheme body arrives unchanged, and the title names the
  # sender's display name at commit. Every identity, message and key below is
  # synthetic.
  use ExUnit.Case, async: false

  @moduletag :test_instance

  alias BnestApp.FamilyChat
  alias BnestApp.PushNotifications
  alias BnestApp.TestInstance
  alias BnestApp.TestInstance.Seed

  @password "Synthetic!Pass1"
  @instance_id "c4c4c4c4c4c4c4c4"
  @admin "test-user-c4c4c4c4-admin"
  @parent "test-user-c4c4c4c4-parent"
  @endpoint "https://push.allowed.example.com/payload-cap"
  @session "cap-session"

  setup do
    run = TestInstance.application_run!()
    assert TestInstance.state() == nil

    on_exit(fn ->
      case TestInstance.state() do
        nil -> :ok
        instance -> TestInstance.drop!(instance)
      end
    end)

    %{run: run}
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A push notification body is collapsed and capped at 120 characters
  test "a dispatched payload caps its body at 120 graphemes and titles the sender", %{run: run} do
    instance = TestInstance.spawn!(run, instance_id: @instance_id, phase: :flat_primary)

    assert {:ok, %{accounts: [%{user_id: admin_id}, %{user_id: parent_id}]}} =
             Seed.apply(instance, "accounts", %{
               "accounts" => [
                 %{"username" => @admin, "password" => @password, "roles" => ["admin"]},
                 %{"username" => @parent, "password" => @password, "roles" => ["parents"]}
               ]
             })

    assert {:ok, %{enabled: true}} =
             PushNotifications.upsert_subscription(admin_id, @session, %{
               "endpoint" => @endpoint,
               "p256dh" => "BBBB",
               "auth" => "AAAA"
             })

    long_body = String.duplicate("kata   \n", 30) <> String.duplicate("z", 60)
    assert String.length(long_body) == 300

    assert {:ok, _message} =
             FamilyChat.send_message(
               parent_id,
               FamilyChat.canonical_room_slug(),
               Ecto.UUID.generate(),
               long_body,
               "Cap Sender"
             )

    assert :ok = PushNotifications.dispatch_all_due!()

    assert_received {:push_notification_sent, @endpoint, long_payload}
    collapsed = long_body |> String.split(~r/\s+/u, trim: true) |> Enum.join(" ")
    assert long_payload["body"] == String.slice(collapsed, 0, 119) <> "…"
    assert String.length(long_payload["body"]) == 120
    assert long_payload["title"] == "Cap Sender"

    exact_body = String.duplicate("y", 120)

    assert {:ok, _message} =
             FamilyChat.send_message(
               parent_id,
               FamilyChat.canonical_room_slug(),
               Ecto.UUID.generate(),
               exact_body,
               "Cap Sender"
             )

    assert :ok = PushNotifications.dispatch_all_due!()

    assert_received {:push_notification_sent, @endpoint, exact_payload}
    assert exact_payload["body"] == exact_body
    assert exact_payload["title"] == "Cap Sender"

    assert :ok = TestInstance.drop!(instance)
  end
end
