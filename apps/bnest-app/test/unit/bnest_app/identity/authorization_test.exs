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
end
