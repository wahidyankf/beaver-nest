defmodule BnestApp.Identity.AuthorizationTest do
  use ExUnit.Case, async: true

  alias BnestApp.Identity.Domain.Authorization
  alias BnestApp.Identity.Domain.Credentials

  test "normalizes only valid ASCII usernames" do
    assert {:ok, {"Family.Admin", "family.admin"}} =
             Credentials.normalize_username("  Family.Admin  ")

    assert {:ok, {"a", "a"}} = Credentials.normalize_username("a")

    assert {:ok, {username, username}} =
             Credentials.normalize_username(String.duplicate("a", 32))

    assert {:error, :invalid_username} = Credentials.normalize_username("")
    assert {:error, :invalid_username} = Credentials.normalize_username(String.duplicate("a", 33))
    assert {:error, :invalid_username} = Credentials.normalize_username("-family")
    assert {:error, :invalid_username} = Credentials.normalize_username("family/")
    assert {:error, :invalid_username} = Credentials.normalize_username("fámily")
    assert {:error, :invalid_username} = Credentials.normalize_username(nil)
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/authentication.feature: Initial setup rejects a password missing a letter, number, or punctuation mark and accepts any length
  test "accepts every valid Unicode password with a letter, number, and punctuation but no character-count rule" do
    assert Credentials.valid_password?("x_1")
    assert Credentials.valid_password?(String.duplicate("é", 129) <> "_1")
    refute Credentials.valid_password?("")
    refute Credentials.valid_password?("password_")
    refute Credentials.valid_password?("password1")
    refute Credentials.valid_password?("123_")
    refute Credentials.valid_password?(<<0xFF, ?a, ?1, ?_>>)
    refute Credentials.valid_password?(nil)
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/authentication.feature: A multi-role user receives only approved capabilities
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/authentication.feature: One authenticated user cannot change another user's data
  test "allows approved self-owned capabilities and defaults all other access to deny" do
    user = %{"userId" => "user-owner", "roles" => ["parents", "admin"]}

    for capability <-
          ~w(use_chat use_sifat_allah use_family_chat read_theme write_theme confirm_import view_import_status)a do
      assert Authorization.allow?(user, capability, "user-owner")
      refute Authorization.allow?(user, capability, "user-other")
    end

    refute Authorization.allow?(user, :manage_accounts, "user-owner")
    refute Authorization.allow?(user, :share_data, "user-other")

    refute Authorization.allow?(
             %{"userId" => "user-owner", "roles" => nil},
             :use_chat,
             "user-owner"
           )

    refute Authorization.allow?(
             %{"userId" => "user-owner", "roles" => ["owner"]},
             :use_chat,
             "user-owner"
           )
  end

  # The family chat resolver refuses with FORBIDDEN exactly when this predicate denies
  # `:use_family_chat`: no persisted account can lack the capability (every storable role
  # grants it), so the refusal is proved here at the decision itself, for an account map
  # whose roles grant nothing.
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A user without family chat capability is forbidden from the room query
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A user without family chat capability is forbidden from sending a message
  test "denies family chat use to an identity whose roles grant nothing" do
    for roles <- [nil, [], ["owner"], ["intruder"]] do
      user = %{"userId" => "user-owner", "roles" => roles}

      refute Authorization.allow?(user, :use_family_chat, "user-owner"),
             "roles #{inspect(roles)} must not use family chat"
    end

    assert Authorization.allow?(
             %{"userId" => "user-owner", "roles" => ["parents"]},
             :use_family_chat,
             "user-owner"
           )
  end
end
