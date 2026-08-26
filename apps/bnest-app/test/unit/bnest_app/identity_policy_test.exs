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

  test "preserves Unicode and whitespace password values within the exact boundaries" do
    assert CredentialVerifier.valid_password?(String.duplicate(" ", 15))
    assert CredentialVerifier.valid_password?(String.duplicate("🙂", 128))
    refute CredentialVerifier.valid_password?(String.duplicate("x", 14))
    refute CredentialVerifier.valid_password?(String.duplicate("🙂", 129))
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
