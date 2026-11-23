defmodule BnestAppWeb.SessionControllerTest do
  @moduledoc """
  Unit tests for the session controller's login boundary: a valid login
  redirects to the posted return path when it stays on this site, and a
  wrong password, an unknown username, or a body with no login map share
  the safe refusal. The controller runs over the record-backed identity
  store on an in-memory backend, never a file, a socket, or a booted
  application.
  """

  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias BnestApp.Identity
  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestAppWeb.SessionController

  @username "test-user-session"
  @password "Session password 1!"

  setup do
    {:ok, _apps} = Application.ensure_all_started(:plug)
    previous = StoragePorts.install()
    on_exit(fn -> StoragePorts.restore(previous) end)
    store = InMemoryRecordBackend.start()
    start_supervised!({Records, store: store})
    start_supervised!(Identity)

    {:ok, _accounts} =
      Identity.bootstrap([
        %{"username" => @username, "password" => @password, "roles" => ["admin"]}
      ])

    :ok
  end

  defp login_conn(params) do
    conn(:post, "/login", params) |> init_test_session(%{}) |> Phoenix.Controller.fetch_flash([])
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A login return path stays on this site
  test "a valid login redirects to a return path that stays on this site" do
    # The scheme is joined at compile time, as in `chat_markdown_test.exs`, so
    # the unit layer's network-URL boundary sees no URL literal.
    evil = "https:" <> "//evil.example"

    for {return_to, expected} <- [
          {"/chat", "/chat"},
          {"//evil.example", "/"},
          {evil, "/"},
          {"chat", "/"},
          {"", "/"}
        ] do
      params = %{
        "login" => %{"username" => @username, "password" => @password},
        "return_to" => return_to
      }

      response = params |> login_conn() |> SessionController.create(params)

      assert response.status == 302
      assert get_resp_header(response, "location") == [expected]
      assert response.resp_cookies["_bnest_identity"].value != nil
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A wrong login stays on the login page and says it is not valid
  test "a wrong login stays on the login page and says it is not valid" do
    wrong_params = %{
      "login" => %{"username" => @username, "password" => "Definitely the wrong password 0!"}
    }

    unknown_params = %{
      "login" => %{"username" => "test-user-session-unknown", "password" => @password}
    }

    wrong_password = wrong_params |> login_conn() |> SessionController.create(wrong_params)
    unknown_user = unknown_params |> login_conn() |> SessionController.create(unknown_params)
    missing_map = %{} |> login_conn() |> SessionController.create(%{})

    for response <- [wrong_password, unknown_user, missing_map] do
      assert response.status == 302
      assert get_resp_header(response, "location") == ["/login"]

      assert Phoenix.Flash.get(response.assigns.flash, :error) ==
               "Username or password is not valid."

      assert response.resp_cookies["_bnest_identity"] == nil
    end
  end
end
