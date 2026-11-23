defmodule BnestAppWeb.HomeLinksTest do
  # The home page offers the Sifat Allah revision activity beside Start
  # chatting, and the Family chat entry only while the room is enabled.
  #
  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Home links to the Sifat Allah revision activity
  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Home shows Family chat only when the room is enabled
  # @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: With family chat off the room is not found, even for a signed-in user
  use ExUnit.Case, async: false

  import Phoenix.HTML.Safe, only: [to_iodata: 1]

  alias BnestAppWeb.PageHTML

  @admin %{
    "displayUsername" => "test-user-unit",
    "roles" => ["admin"],
    "migrationMode" => false
  }

  setup do
    previous = Application.get_env(:bnest_app, :family_chat_enabled)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:bnest_app, :family_chat_enabled),
        else: Application.put_env(:bnest_app, :family_chat_enabled, previous)
    end)

    :ok
  end

  test "offers the Sifat Allah revision activity beside Start chatting" do
    Application.put_env(:bnest_app, :family_chat_enabled, true)
    page = render_home()

    assert page =~ "Misi hafal 40 sifat Allah"
    assert page =~ "/apps/sifat-allah"
    assert page =~ "Start chatting"
  end

  test "offers the Family chat entry only while the room is enabled" do
    Application.put_env(:bnest_app, :family_chat_enabled, true)
    assert render_home() =~ "Family chat"

    Application.put_env(:bnest_app, :family_chat_enabled, false)
    refute render_home() =~ "Family chat"
  end

  defp render_home do
    %{flash: %{}, current_user: @admin}
    |> PageHTML.home()
    |> to_iodata()
    |> IO.iodata_to_binary()
  end
end
