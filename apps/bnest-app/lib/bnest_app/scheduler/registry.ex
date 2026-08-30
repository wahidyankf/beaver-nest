defmodule BnestApp.Scheduler.Registry do
  @moduledoc false

  alias BnestApp.Scheduler.Store

  @entries %{
    "prod_sqlite_backup" => %{
      label: "Production database backup",
      context: "admin_system",
      handler: BnestApp.Backup.Run,
      settings_key: "schedules-backups",
      timezone: "WIB (UTC+07:00)"
    },
    "fixture" => %{
      label: "Family fixture",
      context: "family",
      handler: __MODULE__,
      settings_key: nil,
      timezone: "WIB (UTC+07:00)"
    }
  }

  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(key), do: Map.fetch(@entries, key)

  @spec entries() :: map()
  def entries, do: @entries

  @spec execute(map(), DateTime.t()) :: {:ok, map()}
  def execute(claim, %DateTime{} = now) do
    receipt = %{
      "artifactBasename" => nil,
      "artifactSha256" => nil,
      "artifactBytes" => nil
    }

    :ok = Store.complete(claim.run_id, claim.attempt, receipt, now)
    {:ok, receipt}
  end
end
