defmodule BnestApp.IdentityPolicyTest do
  use ExUnit.Case, async: true

  alias BnestApp.Identity.Authorization
  alias BnestApp.Identity.CredentialVerifier
  alias BnestApp.Identity.FileStore

  test "normalizes only valid ASCII usernames" do
    assert {:ok, {"Family.Admin", "family.admin"}} =
             FileStore.normalize_username("  Family.Admin  ")

    assert {:ok, {"a", "a"}} = FileStore.normalize_username("a")
    assert {:ok, {username, username}} = FileStore.normalize_username(String.duplicate("a", 32))
    assert {:error, :invalid_username} = FileStore.normalize_username("-family")
    assert {:error, :invalid_username} = FileStore.normalize_username("family/")
    assert {:error, :invalid_username} = FileStore.normalize_username("fámily")
  end

  test "accepts every valid Unicode password with a letter, number, and punctuation but no character-count rule" do
    assert CredentialVerifier.valid_password?("x_1")
    assert CredentialVerifier.valid_password?(String.duplicate("é", 129) <> "_1")
    refute CredentialVerifier.valid_password?("")
    refute CredentialVerifier.valid_password?("password_")
    refute CredentialVerifier.valid_password?("password1")
    refute CredentialVerifier.valid_password?("123_")
  end

  test "allows approved self-owned capabilities and defaults all other access to deny" do
    user = %{"userId" => "user-owner", "roles" => ["parents", "admin"]}

    for capability <-
          ~w(use_chat use_sifat_allah read_theme write_theme confirm_import view_import_status)a do
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
  end
end
