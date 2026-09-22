defmodule BnestApp.FamilyChat.MessageTest do
  use ExUnit.Case, async: true

  alias BnestApp.FamilyChat.Message

  describe "normalize_body/1" do
    test "rejects a non-string body outright" do
      assert {:error, :blank} = Message.normalize_body(123)
      assert {:error, :blank} = Message.normalize_body(nil)
      assert {:error, :blank} = Message.normalize_body(%{})
    end
  end

  describe "normalize_reply_to_message_id/1" do
    test "nil passes through as an ordinary message" do
      assert {:ok, nil} = Message.normalize_reply_to_message_id(nil)
    end

    test "a positive integer is accepted, as an integer and as its string form" do
      assert {:ok, 42} = Message.normalize_reply_to_message_id(42)
      assert {:ok, 42} = Message.normalize_reply_to_message_id("42")
    end

    test "zero and negatives are refused" do
      assert {:error, :invalid} = Message.normalize_reply_to_message_id(0)
      assert {:error, :invalid} = Message.normalize_reply_to_message_id(-1)
      assert {:error, :invalid} = Message.normalize_reply_to_message_id("0")
      assert {:error, :invalid} = Message.normalize_reply_to_message_id("-1")
    end

    # `Integer.parse/1` stops at the first non-digit and would happily return
    # 12 for "12abc". This is the case that proves the whole string is checked.
    test "a partially numeric string is refused rather than truncated" do
      assert {:error, :invalid} = Message.normalize_reply_to_message_id("12abc")
      assert {:error, :invalid} = Message.normalize_reply_to_message_id("1.5")
      assert {:error, :invalid} = Message.normalize_reply_to_message_id(" 12")
    end

    test "a non-integer value is refused outright" do
      assert {:error, :invalid} = Message.normalize_reply_to_message_id(%{})
      assert {:error, :invalid} = Message.normalize_reply_to_message_id("")
      assert {:error, :invalid} = Message.normalize_reply_to_message_id(1.0)
    end
  end

  describe "valid_client_message_id?/1" do
    test "rejects a non-string id outright" do
      refute Message.valid_client_message_id?(123)
      refute Message.valid_client_message_id?(nil)
      refute Message.valid_client_message_id?(%{})
    end
  end
end
