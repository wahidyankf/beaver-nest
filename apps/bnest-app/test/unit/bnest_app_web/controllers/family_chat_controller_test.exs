defmodule BnestAppWeb.FamilyChatControllerTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias BnestApp.Test.InMemory.RoomStore, as: InMemoryRoomStore
  alias BnestAppWeb.FamilyChatController

  setup do
    _store = InMemoryRoomStore.install()
    :ok
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A visitor reaches Ruang Keluarga from either family chat address
  test "both family chat addresses reach the Ruang Keluarga room" do
    redirected = FamilyChatController.redirect_to_canonical(conn(:get, "/family-chat"), %{})

    assert redirected.status == 302
    assert get_resp_header(redirected, "location") == ["/family-chat/ruang-keluarga"]

    room_conn =
      conn(:get, "/family-chat/ruang-keluarga")
      |> fetch_query_params()
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])
      |> put_private(:phoenix_format, "html")
      |> assign(:current_user, %{
        "userId" => "test-user-unit",
        "displayUsername" => "Test User"
      })
      |> Phoenix.Controller.put_view(BnestAppWeb.FamilyChatHTML)
      |> FamilyChatController.room(%{"slug" => "ruang-keluarga"})

    assert room_conn.status == 200
    assert room_conn.resp_body =~ "Ruang Keluarga"
  end
end
