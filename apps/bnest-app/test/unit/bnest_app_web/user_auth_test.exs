defmodule BnestAppWeb.UserAuthTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.UserAuth

  test "keeps the legacy browser experience available until cutover is enabled" do
    assert %{
             "userId" => "legacy-browser",
             "displayUsername" => "Local browser",
             "migrationMode" => true
           } = UserAuth.transition_user(false)

    assert UserAuth.transition_user(true) == nil
  end
end
