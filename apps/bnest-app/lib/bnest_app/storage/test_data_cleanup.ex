defmodule BnestApp.Storage.TestDataCleanup do
  @moduledoc false

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config
  alias BnestApp.Storage.Lock
  alias BnestApp.Storage.Migration

  @user_prefix "user-test-"
  @username_prefix "test-user-"
  @legacy_synthetic_user "user-synthetic"
  @legacy_synthetic_app_import "import-synthetic-backup"

  @spec verify(String.t()) :: {:ok, map()} | {:error, atom()}
  def verify(expected_generation) do
    Lock.with_exclusive(fn ->
      with {:ok, %{records: records, recovery_sources: recovery_sources}} <-
             verification(expected_generation) do
        {:ok, %{records: length(records), recovery_sources: length(recovery_sources)}}
      end
    end)
  end

  @spec run(String.t()) :: {:ok, map()} | {:error, atom()}
  def run(expected_generation) do
    Lock.with_exclusive(fn -> purge(expected_generation) end)
  end

  defp purge(expected_generation) do
    with {:ok, %{records: records, recovery_sources: recovery_sources}} <-
           verification(expected_generation) do
      SqliteRepo.transaction(fn ->
        delete_records(records)
        delete_recovery_sources(recovery_sources)
      end)

      :ok = verify_authoritative_database()

      {:ok,
       %{
         records: length(records),
         recovery_sources: length(recovery_sources)
       }}
    end
  end

  defp verification(expected_generation) do
    with {:ok, config} <- Config.read(),
         true <- config["phase"] == "sqlite_primary" || {:error, :not_sqlite_primary},
         true <-
           config["databaseGeneration"] == expected_generation ||
             {:error, :generation_mismatch},
         :ok <- verify_authoritative_database(),
         {:ok, records} <- test_records() do
      {:ok, %{records: records, recovery_sources: test_recovery_sources()}}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :verification_failed}
    end
  end

  defp verify_authoritative_database do
    StorageCoordinator.ensure_started!()

    with %{rows: [["ok"]]} <- SqliteRepo.query!("PRAGMA quick_check"),
         true <-
           SqliteRepo.query!(
             "SELECT state FROM bnest_migration_runs WHERE migration_id = ?",
             [Migration.migration_id()]
           ).rows == [["verified"]] do
      :ok
    else
      _failed -> {:error, :database_not_verified}
    end
  end

  defp test_records do
    SqliteRepo.query!(
      "SELECT record_type, record_key, owner_id, payload_json FROM bnest_records ORDER BY record_type, record_key"
    ).rows
    |> Enum.reduce_while({:ok, []}, fn [type, key, owner_id, payload_json], {:ok, records} ->
      payload = Jason.decode!(payload_json)

      case disposition(type, key, owner_id, payload) do
        :test -> {:cont, {:ok, [{type, key} | records]}}
        :keep -> {:cont, {:ok, records}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp delete_records(records) do
    Enum.each(records, fn {record_type, record_key} ->
      %{num_rows: 1} =
        SqliteRepo.query!(
          "DELETE FROM bnest_records WHERE record_type = ? AND record_key = ?",
          [record_type, record_key]
        )
    end)
  end

  defp delete_recovery_sources(recovery_sources) do
    Enum.each(recovery_sources, fn {owner_kind, owner_key, import_id} ->
      %{num_rows: 1} =
        SqliteRepo.query!(
          "DELETE FROM bnest_recovery_sources WHERE owner_kind = ? AND owner_key = ? AND import_id = ?",
          [owner_kind, owner_key, import_id]
        )
    end)
  end

  defp disposition("bootstrap", _key, _owner_id, %{"accounts" => accounts}) do
    if Enum.any?(accounts, &test_user_id?(&1["userId"])) do
      {:error, :test_data_in_bootstrap}
    else
      :keep
    end
  end

  defp disposition("account", key, _owner_id, payload),
    do: test_if(test_user_id?(key) or test_user_id?(payload["userId"]))

  defp disposition("username-index", key, _owner_id, payload),
    do: test_if(test_username?(key) or test_user_id?(payload["userId"]))

  defp disposition("browser-session", _key, _owner_id, payload),
    do: test_if(test_user_id?(payload["userId"]))

  defp disposition(_type, _key, owner_id, payload),
    do: test_if(test_user_id?(owner_id) or test_user_id?(payload["ownerId"]))

  defp test_recovery_sources do
    SqliteRepo.query!(
      "SELECT owner_kind, owner_key, import_id FROM bnest_recovery_sources ORDER BY owner_kind, owner_key, import_id"
    ).rows
    |> Enum.filter(fn [owner_kind, owner_key, import_id] ->
      legacy_test_recovery?(owner_kind, owner_key, import_id)
    end)
    |> Enum.map(&List.to_tuple/1)
  end

  defp test_if(true), do: :test
  defp test_if(false), do: :keep

  defp test_user_id?(value),
    do: is_binary(value) and String.starts_with?(value, @user_prefix)

  defp test_username?(value),
    do: is_binary(value) and String.starts_with?(value, @username_prefix)

  defp legacy_test_recovery?("user", owner_key, _import_id),
    do: test_user_id?(owner_key) or owner_key == @legacy_synthetic_user

  defp legacy_test_recovery?("app", "beaver-nest", import_id),
    do: import_id == @legacy_synthetic_app_import

  defp legacy_test_recovery?(_owner_kind, _owner_key, _import_id), do: false
end
