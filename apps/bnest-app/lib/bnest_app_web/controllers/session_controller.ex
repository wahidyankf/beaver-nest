defmodule BnestAppWeb.SessionController do
  use BnestAppWeb, :controller

  alias BnestApp.Identity
  alias BnestAppWeb.UserAuth

  @identity_cookie "_bnest_identity"

  def create(conn, %{"login" => %{"username" => username, "password" => password}} = params) do
    case Identity.login(username, password) do
      {:ok, token} ->
        return_to = UserAuth.safe_return_path(params["return_to"] || "/")

        conn
        |> put_resp_cookie(@identity_cookie, token, cookie_options())
        |> redirect(to: return_to)

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Username or password is not valid.")
        |> redirect(to: "/login")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Username or password is not valid.")
    |> redirect(to: "/login")
  end

  def delete(conn, _params) do
    conn = fetch_cookies(conn)
    :ok = Identity.logout(conn.cookies[@identity_cookie])

    conn
    |> delete_resp_cookie(@identity_cookie, cookie_options())
    |> clear_session()
    |> redirect(to: "/login")
  end

  defp cookie_options do
    Application.fetch_env!(:bnest_app, :session_cookie)
    |> Keyword.take([:secure, :same_site, :max_age])
    |> Keyword.put(:http_only, true)
  end
end
