defmodule BnestApp.FamilyChat.Domain.PolicyTest do
  use ExUnit.Case, async: true

  alias BnestApp.FamilyChat.Domain.Policy

  @validation_failed {:error, %{code: "VALIDATION_FAILED", details: nil}}

  test "the canonical room is Ruang Keluarga's slug" do
    assert Policy.canonical_room_slug() == "ruang-keluarga"
  end

  describe "validate_slug/1" do
    test "accepts lowercase words joined by single hyphens, up to 64 bytes" do
      assert Policy.validate_slug("ruang-keluarga") == :ok
      assert Policy.validate_slug("a1") == :ok
      assert Policy.validate_slug(String.duplicate("a", 64)) == :ok
    end

    test "refuses anything else" do
      for slug <- ["", "Ruang", "ruang--keluarga", "-ruang", "ruang-", String.duplicate("a", 65)] do
        assert Policy.validate_slug(slug) == @validation_failed, slug
      end

      assert Policy.validate_slug(nil) == @validation_failed
    end
  end

  test "members post only where member posting is enabled" do
    assert Policy.validate_posting_enabled(%{member_posting_enabled: true}) == :ok

    assert Policy.validate_posting_enabled(%{member_posting_enabled: false}) ==
             {:error, %{code: "FORBIDDEN", details: nil}}
  end

  test "a client message ID must be a UUID" do
    assert Policy.validate_client_message_id("0b9f8a2e-3c41-4d5e-9f60-718293a4b5c6") == :ok
    assert Policy.validate_client_message_id("not-a-uuid") == @validation_failed
  end

  test "a body is normalized, and a blank one refused" do
    assert Policy.validate_body("  hi\r\nthere ") == {:ok, "hi\nthere"}
    assert Policy.validate_body(" \n ") == @validation_failed
  end

  test "a reply target is nil or a positive integer ID" do
    assert Policy.validate_reply_target(nil) == {:ok, nil}
    assert Policy.validate_reply_target("12") == {:ok, 12}
    assert Policy.validate_reply_target("12abc") == @validation_failed
  end

  test "every refusal is a safe error without details" do
    assert Policy.unauthenticated() == {:error, %{code: "UNAUTHENTICATED", details: nil}}
    assert Policy.room_not_found() == {:error, %{code: "ROOM_NOT_FOUND", details: nil}}
    assert Policy.validation_failed() == @validation_failed
    assert Policy.forbidden() == {:error, %{code: "FORBIDDEN", details: nil}}
  end
end
