defmodule BnestAppWeb.Resolvers.WebPushResolverTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.Resolvers.WebPushResolver

  @anonymous %{context: %{}}

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: Push queries and mutations refuse unauthenticated callers
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
