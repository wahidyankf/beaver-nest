defmodule BnestAppWeb.AuthenticationTest do
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BnestApp.DataRepository
  alias BnestApp.Identity

  @tag :unauthenticated
  test "redirects protected navigation before product data is accessed", %{conn: conn} do
    conn = get(conn, "/chat")
    assert redirected_to(conn) == "/login?return_to=%2Fchat"
  end

  test "one-time setup and registration routes are unavailable after closure", %{conn: conn} do
    assert Identity.setup_status() == :closed
    assert get(conn, "/setup").status == 404
    assert post(recycle(conn), "/setup", %{}).status == 404
  end

  test "theme preference is written and cleared only in the authenticated server store", %{
    conn: conn,
    test_identity: identity
  } do
    assert conn |> put("/preferences/theme", %{"theme" => "dark"}) |> response(204)

    assert {:ok, %{"theme" => "dark", "sourceImportId" => nil}} =
             DataRepository.read(:theme, identity.user_id)

    home = conn |> recycle() |> get("/") |> html_response(200)
    assert home =~ ~s(data-theme="dark")
    assert home =~ ~s(data-theme-storage="server")
    assert home =~ ~s(data-browser-persistence="false")

    assert conn |> recycle() |> put("/preferences/theme", %{"theme" => "system"}) |> response(204)
    assert {:error, :missing} = DataRepository.read(:theme, identity.user_id)
    assert conn |> recycle() |> put("/preferences/theme", %{"theme" => "sepia"}) |> response(422)
  end

  @tag :unauthenticated
  test "valid login sets one persistent hardened opaque cookie", %{conn: conn} do
    {username, password} = test_credentials()

    conn =
      post(conn, "/login", %{
        "login" => %{"username" => String.upcase(username), "password" => password},
        "return_to" => "/chat"
      })

    assert redirected_to(conn) == "/chat"
    cookie = get_resp_cookies(conn)["_bnest_identity"]
    assert cookie.http_only
    assert cookie.same_site == "Lax"
    assert cookie.max_age > 60 * 60 * 24 * 365
    refute cookie.secure
    refute cookie.value =~ username

    persisted =
      build_conn()
      |> put_req_cookie("_bnest_identity", cookie.value)
      |> get("/")

    assert html_response(persisted, 200) =~ username
  end

  @tag :unauthenticated
  test "routed HTTPS configuration marks the identity cookie secure", %{conn: conn} do
    previous = Application.fetch_env!(:bnest_app, :session_cookie)
    on_exit(fn -> Application.put_env(:bnest_app, :session_cookie, previous) end)
    Application.put_env(:bnest_app, :session_cookie, Keyword.put(previous, :secure, true))

    {username, password} = test_credentials()

    conn =
      post(conn, "/login", %{
        "login" => %{"username" => username, "password" => password}
      })

    assert get_resp_cookies(conn)["_bnest_identity"].secure
  end

  @tag :unauthenticated
  test "login verification and session reads do not queue behind identity coordination" do
    {username, password} = test_credentials()
    :ok = :sys.suspend(Identity)

    try do
      task = Task.async(fn -> Identity.login(username, password) end)
      assert {:ok, token} = Task.await(task, 5_000)
      assert {:ok, %{"normalizedUsername" => ^username}} = Identity.current_user(token)
      assert :ok = Identity.logout(token)
    after
      :ok = :sys.resume(Identity)
    end
  end

  @tag :unauthenticated
  test "parallel browser logins create independent valid sessions" do
    {username, password} = test_credentials()

    results =
      1..12
      |> Task.async_stream(
        fn _attempt ->
          build_conn()
          |> post("/login", %{"login" => %{"username" => username, "password" => password}})
        end,
        max_concurrency: 12,
        ordered: false,
        timeout: 15_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, fn
             {:ok, conn} -> redirected_to(conn) == "/"
             _failure -> false
           end)

    cookies =
      Enum.map(results, fn {:ok, conn} -> get_resp_cookies(conn)["_bnest_identity"].value end)

    assert cookies |> Enum.uniq() |> length() == 12
    assert Enum.all?(cookies, &match?({:ok, _account}, Identity.current_user(&1)))
  end

  @tag :unauthenticated
  test "invalid usernames and passwords share one safe error", %{conn: conn} do
    {_username, password} = test_credentials()

    missing =
      post(conn, "/login", %{
        "login" => %{"username" => "test-user-missing", "password" => password}
      })

    wrong =
      post(recycle(conn), "/login", %{
        "login" => %{"username" => "test-user-integration", "password" => "wrong password value"}
      })

    assert redirected_to(missing) == "/login"
    assert redirected_to(wrong) == "/login"

    assert Phoenix.Flash.get(missing.assigns.flash, :error) ==
             Phoenix.Flash.get(wrong.assigns.flash, :error)
  end

  @tag :unauthenticated
  test "sanitizes an external post-login return path", %{conn: conn} do
    {username, password} = test_credentials()

    conn =
      post(conn, "/login", %{
        "login" => %{"username" => username, "password" => password},
        "return_to" => "//outside.invalid/private"
      })

    assert redirected_to(conn) == "/"
  end

  @tag :unauthenticated
  test "logout revokes only the presented browser session", %{conn: conn} do
    {username, password} = test_credentials()
    {:ok, token_a} = Identity.login(username, password)
    {:ok, token_b} = Identity.login(username, password)

    conn_a = conn |> put_req_cookie("_bnest_identity", token_a) |> delete("/logout")
    assert redirected_to(conn_a) == "/login"
    assert {:error, :unauthenticated} = Identity.current_user(token_a)
    assert {:ok, _user} = Identity.current_user(token_b)

    browser_b = build_conn() |> put_req_cookie("_bnest_identity", token_b) |> get("/")
    assert html_response(browser_b, 200) =~ username
  end

  @tag :unauthenticated
  test "an unauthenticated LiveView mount cannot trust a client owner", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login?return_to=%2Fchat"}}} = live(conn, "/chat")
  end
end
