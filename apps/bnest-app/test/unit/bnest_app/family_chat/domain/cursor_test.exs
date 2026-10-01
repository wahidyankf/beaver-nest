defmodule BnestApp.FamilyChat.Domain.CursorTest do
  use ExUnit.Case, async: true

  alias BnestApp.FamilyChat.Domain.Cursor

  test "with no options a page is the latest 50" do
    assert Cursor.new([]) == {:ok, %{before_id: nil, after_id: nil, limit: 50}}
  end

  test "names one cursor and a limit from 1 to 50" do
    assert Cursor.new(before_id: 9, limit: 1) == {:ok, %{before_id: 9, after_id: nil, limit: 1}}
    assert Cursor.new(after_id: 3, limit: 50) == {:ok, %{before_id: nil, after_id: 3, limit: 50}}
  end

  test "refuses both cursors at once" do
    assert Cursor.new(before_id: 5, after_id: 1) == :error
  end

  test "refuses a limit outside 1 to 50 or not an integer" do
    for limit <- [0, -1, 51, "10", 1.0, nil] do
      assert Cursor.new(limit: limit) == :error, inspect(limit)
    end
  end
end
