defmodule BnestAppWeb.Resolvers.WebPushResolverTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.Resolvers.WebPushResolver

  @anonymous %{context: %{}}

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: Push queries and mutations refuse unauthenticated callers
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A visitor with no session is refused every Web Push subscription operation
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A signed-in session with no session digest is refused every Web Push subscription operation
  test "a signed-in session with no session digest is refused every Web Push subscription operation" do
    digestless = %{
      context: %{current_user: %{"userId" => "user-digestless"}, session_digest: nil}
    }

    expected =
      {:error, [message: "Authentication required.", extensions: %{code: "UNAUTHENTICATED"}]}

    assert WebPushResolver.current_web_push_subscription(%{}, digestless) == expected

    assert WebPushResolver.upsert_web_push_subscription(%{}, digestless) == expected

    assert WebPushResolver.disable_current_web_push_subscription(%{}, digestless) == expected

    assert {:ok, %{available: available}} =
             WebPushResolver.web_push_configuration(%{}, digestless)

    assert is_boolean(available)
  end

  test "push queries and mutations without an authenticated session are unauthenticated" do
    expected =
      {:error, [message: "Authentication required.", extensions: %{code: "UNAUTHENTICATED"}]}

    assert WebPushResolver.current_web_push_subscription(%{}, @anonymous) == expected

    assert WebPushResolver.upsert_web_push_subscription(%{}, @anonymous) == expected

    assert WebPushResolver.disable_current_web_push_subscription(%{}, @anonymous) == expected

    assert {:ok, %{available: available}} =
             WebPushResolver.web_push_configuration(%{}, @anonymous)

    assert is_boolean(available)
  end
end
