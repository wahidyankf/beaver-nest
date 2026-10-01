defmodule BnestAppWeb.ThemeController do
  use BnestAppWeb, :controller

  alias BnestApp.Identity
  alias BnestApp.Preferences

  # Checked before authorization, so an unknown theme is 422 whoever sends it.
  @themes Preferences.themes()

  def update(conn, %{"theme" => theme}) when theme in @themes do
    user = conn.assigns.current_user
    owner_id = user["userId"]

    if Identity.authorize(user, :write_theme, owner_id) do
      case Preferences.put_theme(owner_id, theme, DateTime.utc_now()) do
        :ok -> send_resp(conn, :no_content, "")
        {:error, _reason} -> send_resp(conn, :conflict, "Theme preference was not changed.")
      end
    else
      send_resp(conn, :forbidden, "Forbidden")
    end
  end

  def update(conn, _params), do: send_resp(conn, :unprocessable_entity, "Invalid theme.")
end
