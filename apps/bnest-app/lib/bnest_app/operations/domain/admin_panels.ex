defmodule BnestApp.Operations.Domain.AdminPanels do
  @moduledoc """
  The typed admin settings panels the contexts declare: where each panel lives, which
  context owns it, and the only fields that owner validates and saves. The owner is the
  owning context's facade, which the admin settings page renders as `data-config-owner`.
  """

  @type panel :: %{
          key: String.t(),
          label: String.t(),
          description: String.t(),
          path: String.t(),
          owner: module(),
          editable_fields: [String.t()]
        }

  @panels [
    %{
      key: "data-storage",
      label: "Data storage",
      description: "Authoritative SQLite location and migration status",
      path: "/storage",
      owner: BnestApp.Storage,
      editable_fields: []
    },
    %{
      key: "schedules-backups",
      label: "Schedules & backups",
      description: "Daily jobs and verified production database backups",
      path: "/admin/settings/schedules",
      owner: BnestApp.Backup,
      editable_fields: ["destination_directory", "enabled", "daily_time_wib"]
    }
  ]

  @spec panels() :: [panel()]
  def panels, do: @panels

  @spec fetch(String.t()) :: {:ok, panel()} | :error
  def fetch(key), do: Enum.find_value(@panels, :error, &if(&1.key == key, do: {:ok, &1}))
end
