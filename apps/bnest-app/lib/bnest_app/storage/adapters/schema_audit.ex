defmodule BnestApp.Storage.Adapters.SchemaAudit do
  @moduledoc """
  Audits the record structure of a runtime root on disk. It reports only each record's type,
  version and result, never its contents, and it refuses any root other than the production
  data directory or a marked test run.
  """

  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.RecordSchema

  @spec audit_root(String.t()) :: {:ok, [map()]} | {:error, atom()}
  def audit_root(root) when is_binary(root) do
    root = Path.expand(root)
    kinds = Storage.record_kinds()

    with :ok <- audit_root_allowed(root, kinds) do
      results =
        root
        |> Path.join("**/*.json")
        |> Path.wildcard()
        |> Enum.reject(&(Path.basename(&1) == ".bnest-test-run.json"))
        |> Enum.map(&audit_file(&1, kinds))
        |> Enum.uniq()
        |> Enum.sort_by(&{&1["recordType"], &1["schemaVersion"], &1["result"]})

      {:ok, results}
    end
  end

  defp audit_file(path, kinds) do
    case File.read(path) do
      {:ok, bytes} -> audit_bytes(bytes, kinds)
      {:error, _reason} -> audit_result(nil, nil, "fail")
    end
  end

  defp audit_bytes(bytes, kinds) do
    case Jason.decode(bytes) do
      {:ok, record} when is_map(record) ->
        result =
          if match?({:ok, _record}, RecordSchema.validate(record, kinds)),
            do: "pass",
            else: "fail"

        audit_result(record["recordType"], record["schemaVersion"], result)

      _invalid ->
        audit_result(nil, nil, "fail")
    end
  end

  defp audit_result(record_type, schema_version, result) do
    %{
      "recordType" => record_type || "unknown",
      "schemaVersion" => schema_version || "unknown",
      "result" => result
    }
  end

  defp audit_root_allowed(root, kinds) do
    cond do
      symlink?(root) -> {:error, :symlink}
      not File.dir?(root) -> {:error, :missing_root}
      String.ends_with?(root, "/data/prod") -> :ok
      String.contains?(root, "/data/test/runs/") -> marked_test_root?(root, kinds)
      true -> {:error, :unsupported_root}
    end
  end

  defp marked_test_root?(root, kinds) do
    with {:ok, bytes} <- File.read(Path.join(root, ".bnest-test-run.json")),
         {:ok, marker} <- Jason.decode(bytes),
         {:ok, ^marker} <- RecordSchema.validate(marker, kinds),
         true <- marker["runId"] == Path.basename(root) do
      :ok
    else
      _invalid -> {:error, :invalid_test_marker}
    end
  end

  defp symlink?(path) do
    match?({:ok, %File.Stat{type: :symlink}}, File.lstat(path))
  end
end
