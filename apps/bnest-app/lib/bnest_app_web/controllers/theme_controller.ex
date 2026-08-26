defmodule BnestAppWeb.ThemeController do
  use BnestAppWeb, :controller

  alias BnestApp.DataRepository
  alias BnestApp.Identity

  def update(conn, %{"theme" => theme}) when theme in ["system", "light", "dark"] do
    user = conn.assigns.current_user
    owner_id = user["userId"]

    if Identity.authorize(user, :write_theme, owner_id) do
      case persist(owner_id, theme) do
        :ok -> send_resp(conn, :no_content, "")
        {:error, _reason} -> send_resp(conn, :conflict, "Theme preference was not changed.")
      end
    else
      send_resp(conn, :forbidden, "Forbidden")
    end
  end

  def update(conn, _params), do: send_resp(conn, :unprocessable_entity, "Invalid theme.")

  defp persist(owner_id, "system") do
    case DataRepository.read(:theme, owner_id) do
      {:ok, record} -> DataRepository.remove_exact(:theme, owner_id, record)
      {:error, :missing} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist(owner_id, theme) do
    case DataRepository.read(:theme, owner_id) do
      {:ok, record} -> write(owner_id, theme, record)
      {:error, :missing} -> write(owner_id, theme, nil)
      {:error, reason} -> {:error, reason}
    end
  end

  defp write(owner_id, theme, existing) do
    candidate = %{
      "schemaVersion" => 1,
      "recordType" => "theme-preference",
      "ownerId" => owner_id,
      "sourceImportId" => if(existing, do: existing["sourceImportId"], else: nil),
      "theme" => theme,
      "updatedAt" => timestamp()
    }

    expected_revision = if existing, do: existing["revision"], else: nil

    case DataRepository.write(:theme, owner_id, expected_revision, candidate) do
      {:ok, _record} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
