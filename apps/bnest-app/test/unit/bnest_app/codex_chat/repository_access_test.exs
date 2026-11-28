defmodule BnestApp.CodexChat.RepositoryAccessTest do
  use ExUnit.Case, async: true

  alias BnestApp.CodexChat.Domain.RepositoryAccess

  test "only administrators without the children role may enable writes" do
    assert RepositoryAccess.can_enable_write?(%{"roles" => ["admin"]})
    assert RepositoryAccess.can_enable_write?(%{"roles" => ["parents", "admin"]})

    refute RepositoryAccess.can_enable_write?(%{"roles" => ["children"]})
    refute RepositoryAccess.can_enable_write?(%{"roles" => ["parents"]})
    refute RepositoryAccess.can_enable_write?(%{"roles" => ["children", "admin"]})
    refute RepositoryAccess.can_enable_write?(%{"roles" => ["children", "parents", "admin"]})
    refute RepositoryAccess.can_enable_write?(%{"roles" => ["unknown"]})
    refute RepositoryAccess.can_enable_write?(%{"roles" => ["admin", "unknown"]})
    refute RepositoryAccess.can_enable_write?(%{"roles" => ["admin", "admin"]})
    refute RepositoryAccess.can_enable_write?(%{})
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: An administrator turns repository writes on and off
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Repository access returns to read-only after a reload or after clearing the chat
  test "mode fails closed unless an eligible administrator explicitly requests writes" do
    assert RepositoryAccess.mode(%{"roles" => ["admin"]}, false) == :read_only
    assert RepositoryAccess.mode(%{"roles" => ["admin"]}, true) == :workspace_write
    assert RepositoryAccess.mode(%{"roles" => ["children", "admin"]}, true) == :read_only
    assert RepositoryAccess.mode(%{}, true) == :read_only
    assert RepositoryAccess.mode(%{"roles" => ["admin"]}, "true") == :read_only
  end
end
