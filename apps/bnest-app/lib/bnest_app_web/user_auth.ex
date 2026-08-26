defmodule BnestAppWeb.UserAuth do
  @moduledoc false

  import Phoenix.Controller
  import Plug.Conn

  alias BnestApp.DataRepository
  alias BnestApp.Identity

  @identity_cookie "_bnest_identity"
  @legacy_transition_user %{
    "userId" => "legacy-browser",
    "displayUsername" => "Local browser",
    "roles" => ["admin", "parents", "children"],
    "migrationMode" => true
  }

  def fetch_current_user(conn, _options) do
    conn = fetch_cookies(conn)

    case Identity.current_user(conn.cookies[@identity_cookie]) do
      {:ok, user} ->
        conn
        |> assign(:current_user, user)
        |> assign(:current_theme, current_theme(user))
        |> assign(:theme_storage, :server)
        |> put_session(:current_user, user)

      {:error, :unauthenticated} ->
        case transition_user(cutover_enabled?()) do
          nil ->
            conn
            |> assign(:current_user, nil)
            |> assign(:current_theme, "system")
            |> assign(:theme_storage, :browser)
            |> delete_session(:current_user)

          user ->
            conn
            |> assign(:current_user, user)
            |> assign(:current_theme, "system")
            |> assign(:theme_storage, :browser)
            |> put_session(:current_user, user)
        end
    end
  end

  @doc false
  def transition_user(false), do: @legacy_transition_user
  def transition_user(true), do: nil

  @doc false
  def cutover_enabled?, do: Application.get_env(:bnest_app, :identity_cutover_enabled, false)

  def require_authenticated_user(%{assigns: %{current_user: user}} = conn, _options)
      when not is_nil(user),
      do: conn

  def require_authenticated_user(conn, _options) do
    return_to = safe_return_path(conn.request_path)

    conn
    |> put_flash(:error, "Please log in to continue.")
    |> redirect(to: "/login?return_to=#{URI.encode_www_form(return_to)}")
    |> halt()
  end

  def require_open_setup(conn, _options) do
    case {cutover_enabled?(), Identity.setup_status()} do
      {true, :open} -> conn
      _closed_or_invalid -> conn |> send_resp(:not_found, "Not found") |> halt()
    end
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    case session["current_user"] do
      %{"userId" => _user_id} = user ->
        {:cont, Phoenix.Component.assign(socket, :current_user, user)}

      _missing ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
    end
  end

  def safe_return_path(path) when is_binary(path) do
    uri = URI.parse(path)

    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") and
         is_nil(uri.scheme) and is_nil(uri.host),
       do: path,
       else: "/"
  end

  def safe_return_path(_path), do: "/"

  defp current_theme(%{"userId" => user_id}) do
    case DataRepository.read(:theme, user_id) do
      {:ok, %{"theme" => theme}} -> theme
      {:error, _missing_or_invalid} -> "system"
    end
  end
end
