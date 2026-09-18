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

  describe "valid_client_message_id?/1" do
    test "rejects a non-string id outright" do
      refute Message.valid_client_message_id?(123)
      refute Message.valid_client_message_id?(nil)
      refute Message.valid_client_message_id?(%{})
    end
  end
end
