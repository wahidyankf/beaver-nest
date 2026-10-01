defmodule BnestApp.Storage.Domain.RecordSchema do
  @moduledoc """
  The version-1 record schema. Storage owns every record envelope; a registered
  `BnestApp.Storage.Ports.RecordKind` owns the remaining fields of its own record type.
  """

  @roles ~w(children parents admin)
  @statuses ~w(pending retryable rejected accepted)
  @failures ~w(unsupported-version unsupported-source oversized malformed owner-unresolved stale-revision write-failed read-back-failed cleanup-pending)
  @id_pattern ~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}\z/u
  @username_pattern ~r/\A[a-z0-9](?:[a-z0-9._-]{0,30}[a-z0-9])?\z/u
  @sha_pattern ~r/\A[0-9a-f]{64}\z/u
  @envelope ~w(schemaVersion recordType ownerId sourceImportId revision updatedAt)

  @spec validate(term(), [module()]) :: {:ok, map()} | {:error, atom()}
  def validate(%{"schemaVersion" => version}, _kinds) when version != 1,
    do: {:error, :unsupported_version}

  def validate(%{"schemaVersion" => 1, "recordType" => type} = record, kinds) do
    case validate_type(type, record, kinds) do
      true -> {:ok, record}
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_schema}
    end
  end

  def validate(_record, _kinds), do: {:error, :invalid_schema}

  @doc "The envelope fields every kind-owned record carries besides its own fields."
  @spec envelope_fields() :: [String.t()]
  def envelope_fields, do: @envelope

  @spec structural_projection(map()) :: map()
  def structural_projection(record) when is_map(record) do
    %{
      "recordType" => record["recordType"],
      "schemaVersion" => record["schemaVersion"],
      "fields" => Map.new(record, fn {key, value} -> {key, type_name(value)} end)
    }
  end

  @doc "Whether `value` is a stable record identifier."
  @spec id?(term()) :: boolean()
  def id?(value), do: is_binary(value) and Regex.match?(@id_pattern, value)

  @doc "Whether `values` is a non-empty list whose every element satisfies `predicate`."
  @spec nonempty_list?(term(), (term() -> boolean())) :: boolean()
  def nonempty_list?(values, predicate),
    do: is_list(values) and values != [] and Enum.all?(values, predicate)

  @doc "Whether `map` holds exactly `keys`."
  @spec exact?(term(), [String.t()]) :: boolean()
  def exact?(map, keys) when is_map(map), do: Map.keys(map) |> Enum.sort() == Enum.sort(keys)
  def exact?(_map, _keys), do: false

  @doc "Whether `value` is a non-negative revision or index."
  @spec revision?(term()) :: boolean()
  def revision?(value), do: is_integer(value) and value >= 0

  defp validate_type("bootstrap", record, _kinds) do
    exact?(record, ~w(schemaVersion recordType state attemptId startedAt closedAt accounts)) and
      record["state"] in ~w(pending closed) and id?(record["attemptId"]) and
      timestamp?(record["startedAt"]) and bootstrap_closed_at?(record) and
      nonempty_list?(record["accounts"], &bootstrap_account?/1)
  end

  defp validate_type("account", record, _kinds) do
    exact?(
      record,
      ~w(schemaVersion recordType userId displayUsername normalizedUsername roles passwordVerifier createdAt)
    ) and
      id?(record["userId"]) and display_username?(record["displayUsername"]) and
      username?(record["normalizedUsername"]) and roles?(record["roles"]) and
      argon2id?(record["passwordVerifier"]) and timestamp?(record["createdAt"])
  end

  defp validate_type("username-index", record, _kinds) do
    exact?(record, ~w(schemaVersion recordType normalizedUsername userId)) and
      username?(record["normalizedUsername"]) and id?(record["userId"])
  end

  defp validate_type("browser-session", record, _kinds) do
    exact?(record, ~w(schemaVersion recordType tokenDigest userId issuedAt revokedAt)) and
      sha?(record["tokenDigest"]) and id?(record["userId"]) and timestamp?(record["issuedAt"]) and
      nullable_timestamp?(record["revokedAt"])
  end

  defp validate_type("browser-import", record, _kinds) do
    if browser_import_shape?(record), do: validate_browser_import_content(record), else: false
  end

  defp validate_type("theme-preference", record, _kinds) do
    exact?(record, ~w(schemaVersion recordType ownerId sourceImportId revision theme updatedAt)) and
      id?(record["ownerId"]) and nullable_id?(record["sourceImportId"]) and
      revision?(record["revision"]) and record["theme"] in ~w(light dark) and
      timestamp?(record["updatedAt"])
  end

  defp validate_type("import-manifest", record, _kinds) do
    manifest_shape?(record) and manifest_identity?(record) and manifest_lifecycle?(record)
  end

  defp validate_type("schema-registry", record, _kinds) do
    exact?(record, ~w(schemaVersion recordType supported migrations)) and
      is_map(record["supported"]) and map_size(record["supported"]) > 0 and
      Enum.all?(record["supported"], fn {type, versions} ->
        is_binary(type) and nonempty_list?(versions, &positive?/1)
      end) and is_list(record["migrations"]) and
      Enum.all?(record["migrations"], &migration?/1)
  end

  defp validate_type("bnest-test-run", record, _kinds) do
    marker_shape?(record) and id?(record["runId"]) and timestamp?(record["createdAt"]) and
      record["owner"] == "bnest-test-harness"
  end

  defp validate_type(type, record, kinds) do
    case Enum.find(kinds, &(&1.record_type() == type)) do
      nil -> false
      kind -> owned_envelope?(record) and kind.valid?(record)
    end
  end

  defp owned_envelope?(record) do
    id?(record["ownerId"]) and nullable_id?(record["sourceImportId"]) and
      revision?(record["revision"]) and timestamp?(record["updatedAt"])
  end

  defp marker_shape?(record) do
    exact?(record, ~w(schemaVersion recordType runId createdAt owner)) or
      (exact?(record, ~w(schemaVersion recordType runId createdAt owner pid hostname)) and
         is_binary(record["pid"]) and is_binary(record["hostname"]))
  end

  defp browser_import_shape?(record) do
    exact?(
      record,
      ~w(schemaVersion recordType importId ownerId source payloadEncoding payload integrity)
    ) and
      id?(record["importId"]) and id?(record["ownerId"]) and
      record["payloadEncoding"] == "utf8-string" and is_binary(record["payload"]) and
      exact?(record["integrity"], ~w(sha256 capturedAt)) and
      sha?(record["integrity"]["sha256"]) and timestamp?(record["integrity"]["capturedAt"])
  end

  defp validate_browser_import_content(record) do
    cond do
      not supported_source?(record["source"]) ->
        {:error, :unsupported_source}

      byte_size(record["payload"]) > source_limit(record["source"]["storageKey"]) ->
        {:error, :oversized}

      digest(record["payload"]) != record["integrity"]["sha256"] ->
        {:error, :checksum_mismatch}

      true ->
        true
    end
  end

  defp manifest_shape?(record) do
    exact?(
      record,
      ~w(schemaVersion recordType importId ownerId source destination recoverySource status attempt startedAt completedAt failureCategory)
    )
  end

  defp manifest_identity?(record) do
    id?(record["importId"]) and nullable_id?(record["ownerId"]) and
      manifest_source?(record["source"]) and destination?(record["destination"]) and
      recovery_source?(record["recoverySource"])
  end

  defp manifest_lifecycle?(record) do
    record["status"] in @statuses and positive?(record["attempt"]) and
      timestamp?(record["startedAt"]) and nullable_timestamp?(record["completedAt"]) and
      (is_nil(record["failureCategory"]) or record["failureCategory"] in @failures)
  end

  defp bootstrap_account?(account) do
    exact?(account, ~w(userId normalizedUsername accountSha256 indexSha256)) and
      id?(account["userId"]) and username?(account["normalizedUsername"]) and
      sha?(account["accountSha256"]) and sha?(account["indexSha256"])
  end

  defp bootstrap_closed_at?(%{"state" => "pending", "closedAt" => nil}), do: true
  defp bootstrap_closed_at?(%{"state" => "closed", "closedAt" => value}), do: timestamp?(value)
  defp bootstrap_closed_at?(_record), do: false

  defp supported_source?(source) do
    exact?(source, ~w(kind storageArea storageKey sourceSchemaVersion)) and
      source["kind"] == "browser-storage" and positive?(source["sourceSchemaVersion"]) and
      {source["storageArea"], source["storageKey"]} in [
        {"sessionStorage", "bnest.chat.v1"},
        {"localStorage", "bnest.sifat-allah.v1"},
        {"localStorage", "phx:theme"}
      ]
  end

  defp source_limit("bnest.chat.v1"), do: 500_000
  defp source_limit("bnest.sifat-allah.v1"), do: 10_000
  defp source_limit("phx:theme"), do: 16

  defp manifest_source?(source),
    do:
      exact?(source, ~w(kind reference sha256)) and is_binary(source["kind"]) and
        is_binary(source["reference"]) and sha?(source["sha256"])

  defp destination?(destination),
    do:
      exact?(destination, ~w(recordType relativePathTemplate)) and
        is_binary(destination["recordType"]) and is_binary(destination["relativePathTemplate"])

  defp recovery_source?(source),
    do:
      exact?(source, ~w(kind relativePathTemplate sha256)) and is_binary(source["kind"]) and
        is_binary(source["relativePathTemplate"]) and sha?(source["sha256"])

  defp migration?(migration),
    do:
      exact?(migration, ~w(recordType from to migrationId)) and
        is_binary(migration["recordType"]) and positive?(migration["from"]) and
        positive?(migration["to"]) and migration["to"] > migration["from"] and
        id?(migration["migrationId"])

  defp nullable_id?(nil), do: true
  defp nullable_id?(value), do: id?(value)
  defp sha?(value), do: is_binary(value) and Regex.match?(@sha_pattern, value)
  defp username?(value), do: is_binary(value) and Regex.match?(@username_pattern, value)
  defp display_username?(value), do: is_binary(value) and String.length(value) in 1..32
  defp argon2id?(value), do: is_binary(value) and String.starts_with?(value, "$argon2id$")
  defp positive?(value), do: is_integer(value) and value > 0

  defp roles?(roles),
    do: nonempty_list?(roles, &(&1 in @roles)) and Enum.uniq(roles) == roles

  defp timestamp?(value) when is_binary(value),
    do: match?({:ok, _time, 0}, DateTime.from_iso8601(value))

  defp timestamp?(_value), do: false
  defp nullable_timestamp?(nil), do: true
  defp nullable_timestamp?(value), do: timestamp?(value)

  defp digest(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp type_name(nil), do: "null"
  defp type_name(value) when is_binary(value), do: "string"
  defp type_name(value) when is_integer(value), do: "integer"
  defp type_name(value) when is_float(value), do: "number"
  defp type_name(value) when is_boolean(value), do: "boolean"
  defp type_name(value) when is_list(value), do: "array"
  defp type_name(value) when is_map(value), do: "object"
end
