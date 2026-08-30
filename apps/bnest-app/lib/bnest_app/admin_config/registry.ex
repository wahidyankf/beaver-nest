defmodule BnestApp.AdminConfig.Registry do
  @moduledoc false

  @panels [
    %{
      key: "data-storage",
      label: "Data storage",
      description: "Authoritative SQLite location and migration status",
      path: "/storage",
      owner: BnestApp.Storage.Config,
      editable_fields: []
    },
    %{
      key: "schedules-backups",
      label: "Schedules & backups",
      description: "Daily jobs and verified production database backups",
      path: "/admin/settings/schedules",
      owner: BnestApp.Backup.Config,
      editable_fields: ["destination_directory", "enabled", "daily_time_wib"]
    }
  ]

  @spec panels() :: [map()]
  def panels, do: @panels

  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(key), do: Enum.find_value(@panels, :error, &if(&1.key == key, do: {:ok, &1}))
end
